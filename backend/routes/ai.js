const express = require("express");
const auth = require("../middleware/auth");
const Memory = require("../models/Memory");
const gemini = require("../services/geminiService");

const router = express.Router();

// Helper: apply Cloudinary face-crop transformation to a URL
function faceCropUrl(url, size = 200) {
  if (!url) return null;
  return url.replace(
    "/upload/",
    `/upload/c_thumb,g_face,w_${size},h_${size},z_0.7/`,
  );
}

router.use(auth);

/**
 * GET /api/ai/status
 * Check if AI features are available
 */
router.get("/status", (req, res) => {
  res.json({ enabled: gemini.enabled });
});

/**
 * POST /api/ai/analyze/:memoryId
 * Analyze a memory's first image with Gemini
 */
router.post("/analyze/:memoryId", async (req, res, next) => {
  try {
    if (!gemini.enabled) {
      return res
        .status(503)
        .json({ error: "AI features not configured. Set GEMINI_API_KEY." });
    }

    const memory = await Memory.findById(req.params.memoryId).lean();
    if (!memory) {
      return res.status(404).json({ error: "Memory not found" });
    }

    const photoItem = memory.mediaItems.find((item) => item.type === "photo");
    if (!photoItem) {
      return res
        .status(400)
        .json({ error: "No photo found in this memory to analyze" });
    }

    const imageUrl = photoItem.cloudinaryUrl || photoItem.url;
    const analysis = await gemini.analyzeImage(imageUrl);

    // Optionally auto-update the memory with AI-generated title/description
    if (req.query.apply === "true") {
      await Memory.findByIdAndUpdate(req.params.memoryId, {
        $set: {
          title: analysis.title,
          description: analysis.description,
          tags: analysis.tags,
          mood: analysis.mood,
        },
      });
    }

    res.json(analysis);
  } catch (err) {
    console.error("AI analyze error:", err.message);
    res.status(500).json({ error: err.message || "AI analysis failed" });
  }
});

/**
 * POST /api/ai/analyze-url
 * Analyze an image by URL (for preview before saving)
 */
router.post("/analyze-url", async (req, res, next) => {
  try {
    if (!gemini.enabled) {
      return res.status(503).json({ error: "AI features not configured" });
    }

    const { imageUrl } = req.body;
    if (!imageUrl) {
      return res.status(400).json({ error: "imageUrl is required" });
    }

    const analysis = await gemini.analyzeImage(imageUrl);
    res.json(analysis);
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/ai/highlights
 * Get AI-powered highlights: On This Day + recent AI insights
 */
router.get("/highlights", async (req, res, next) => {
  try {
    const now = new Date();
    const today = now.getDate();
    const month = now.getMonth();

    const allMemories = await Memory.find().sort({ createdAt: -1 }).lean();

    // "On This Day" — memories from this week in previous years (wider match)
    const onThisDay = allMemories.filter((m) => {
      const d = new Date(m.createdAt);
      if (d.getFullYear() === now.getFullYear()) return false;
      const dayDiff = Math.abs(
        d.getMonth() * 31 + d.getDate() - (month * 31 + today),
      );
      return dayDiff <= 3; // within 3 days of this date in past years
    });

    // Recent memories (last 7 days) for AI analysis
    const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const recentMemories = allMemories.filter(
      (m) => new Date(m.createdAt) >= weekAgo,
    );

    // Generate AI story for recent memories if available
    let weeklyStory = null;
    if (gemini.enabled && recentMemories.length >= 2) {
      try {
        const imageUrls = recentMemories
          .flatMap((m) => m.mediaItems)
          .filter((item) => item.type === "photo")
          .map((item) => item.cloudinaryUrl || item.url)
          .slice(0, 4);

        if (imageUrls.length >= 2) {
          weeklyStory = await gemini.generateStory(imageUrls);
        }
      } catch (e) {
        console.error("Failed to generate weekly story:", e.message);
      }
    }

    // Stats
    const totalMemories = allMemories.length;
    const totalPhotos = allMemories.reduce(
      (sum, m) => sum + m.mediaItems.filter((i) => i.type === "photo").length,
      0,
    );
    const totalVideos = allMemories.reduce(
      (sum, m) => sum + m.mediaItems.filter((i) => i.type === "video").length,
      0,
    );

    // Unique locations
    const locations = [
      ...new Set(allMemories.map((m) => m.location?.name).filter(Boolean)),
    ];

    res.json({
      onThisDay,
      weeklyStory,
      recentCount: recentMemories.length,
      stats: {
        totalMemories,
        totalPhotos,
        totalVideos,
        locations: locations.length,
      },
    });
  } catch (err) {
    console.error("AI highlights error:", err.message);
    res.status(500).json({ error: err.message || "Failed to load highlights" });
  }
});

/**
 * GET /api/ai/weekly-recap
 * Get detailed weekly recap with AI-generated story
 */
router.get("/weekly-recap", async (req, res, next) => {
  try {
    const now = new Date();
    const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    const memories = await Memory.find({
      createdAt: { $gte: weekAgo },
    })
      .sort({ createdAt: -1 })
      .lean();

    if (memories.length === 0) {
      return res.json({ recap: null });
    }

    const locations = [
      ...new Set(memories.map((m) => m.location?.name).filter(Boolean)),
    ];
    const moods = [...new Set(memories.map((m) => m.mood).filter(Boolean))];
    const titles = memories.map((m) => m.title).filter(Boolean);
    const imageUrls = memories
      .flatMap((m) => m.mediaItems)
      .filter((i) => i.type === "photo")
      .map((i) => i.cloudinaryUrl || i.url);
    const coverPhoto = imageUrls[0] || null;

    let aiRecap = null;
    if (gemini.enabled && memories.length >= 1) {
      try {
        aiRecap = await gemini.generateRecap(
          {
            period: "weekly",
            memoryCount: memories.length,
            locations,
            moods,
            titles,
            dateRange: `${weekAgo.toLocaleDateString()} - ${now.toLocaleDateString()}`,
          },
          imageUrls.slice(0, 4),
        );
      } catch (e) {
        console.error("Weekly recap AI failed:", e.message);
      }
    }

    res.json({
      recap: {
        period: "weekly",
        dateRange: {
          start: weekAgo.toISOString(),
          end: now.toISOString(),
        },
        memoryCount: memories.length,
        photoCount: imageUrls.length,
        locations,
        moods,
        coverPhoto,
        memories: memories.slice(0, 20),
        ai: aiRecap,
      },
    });
  } catch (err) {
    console.error("Weekly recap error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/ai/monthly-recap
 * Get detailed monthly recap with AI-generated story
 */
router.get("/monthly-recap", async (req, res, next) => {
  try {
    const now = new Date();
    const monthAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

    const memories = await Memory.find({
      createdAt: { $gte: monthAgo },
    })
      .sort({ createdAt: -1 })
      .lean();

    if (memories.length === 0) {
      return res.json({ recap: null });
    }

    const locations = [
      ...new Set(memories.map((m) => m.location?.name).filter(Boolean)),
    ];
    const moods = [...new Set(memories.map((m) => m.mood).filter(Boolean))];
    const titles = memories.map((m) => m.title).filter(Boolean);
    const imageUrls = memories
      .flatMap((m) => m.mediaItems)
      .filter((i) => i.type === "photo")
      .map((i) => i.cloudinaryUrl || i.url);
    const coverPhoto = imageUrls[0] || null;

    // Group by week
    const weeks = {};
    for (const m of memories) {
      const d = new Date(m.createdAt);
      const weekNum = Math.ceil(
        (now.getTime() - d.getTime()) / (7 * 24 * 60 * 60 * 1000),
      );
      const key = `week_${weekNum}`;
      if (!weeks[key]) weeks[key] = [];
      weeks[key].push(m);
    }

    let aiRecap = null;
    if (gemini.enabled && memories.length >= 2) {
      try {
        aiRecap = await gemini.generateRecap(
          {
            period: "monthly",
            memoryCount: memories.length,
            locations,
            moods,
            titles,
            dateRange: `${monthAgo.toLocaleDateString()} - ${now.toLocaleDateString()}`,
          },
          imageUrls.slice(0, 4),
        );
      } catch (e) {
        console.error("Monthly recap AI failed:", e.message);
      }
    }

    res.json({
      recap: {
        period: "monthly",
        dateRange: {
          start: monthAgo.toISOString(),
          end: now.toISOString(),
        },
        memoryCount: memories.length,
        photoCount: imageUrls.length,
        locations,
        moods,
        coverPhoto,
        weeklyBreakdown: Object.entries(weeks).map(([key, mems]) => ({
          week: key,
          count: mems.length,
          coverPhoto:
            mems.flatMap((m) => m.mediaItems).find((i) => i.type === "photo")
              ?.cloudinaryUrl || null,
        })),
        memories: memories.slice(0, 30),
        ai: aiRecap,
      },
    });
  } catch (err) {
    console.error("Monthly recap error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/ai/discover
 * Unified discovery endpoint — aggregates all smart features
 */
router.get("/discover", async (req, res, next) => {
  try {
    const now = new Date();
    const today = now.getDate();
    const month = now.getMonth();
    const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const monthAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

    const allMemories = await Memory.find().sort({ createdAt: -1 }).lean();

    // On This Day (within 3 days of today in past years)
    const onThisDay = allMemories.filter((m) => {
      const d = new Date(m.createdAt);
      if (d.getFullYear() === now.getFullYear()) return false;
      const dayDiff = Math.abs(
        d.getMonth() * 31 + d.getDate() - (month * 31 + today),
      );
      return dayDiff <= 3;
    });

    // Recent memories
    const recentMemories = allMemories.filter(
      (m) => new Date(m.createdAt) >= weekAgo,
    );
    const monthlyMemories = allMemories.filter(
      (m) => new Date(m.createdAt) >= monthAgo,
    );

    // Weekly summary (without AI call — just metadata)
    const weeklyLocations = [
      ...new Set(recentMemories.map((m) => m.location?.name).filter(Boolean)),
    ];
    const weeklyMoods = [
      ...new Set(recentMemories.map((m) => m.mood).filter(Boolean)),
    ];
    const weeklyCover =
      recentMemories
        .flatMap((m) => m.mediaItems)
        .find((i) => i.type === "photo")?.cloudinaryUrl || null;

    // Monthly summary
    const monthlyLocations = [
      ...new Set(monthlyMemories.map((m) => m.location?.name).filter(Boolean)),
    ];
    const monthlyCover =
      monthlyMemories
        .flatMap((m) => m.mediaItems)
        .find((i) => i.type === "photo")?.cloudinaryUrl || null;

    // People across all memories
    const peopleMap = {};
    for (const m of allMemories) {
      if (m.people && m.people.length > 0) {
        for (const person of m.people) {
          const key = person.label || person.description || "Unknown";
          if (!peopleMap[key]) {
            peopleMap[key] = { label: key, count: 0, thumbnail: null };
          }
          peopleMap[key].count++;
          if (!peopleMap[key].thumbnail) {
            const photo = m.mediaItems.find((i) => i.type === "photo");
            if (photo)
              peopleMap[key].thumbnail = faceCropUrl(photo.cloudinaryUrl);
          }
        }
      }
    }
    const people = Object.values(peopleMap)
      .sort((a, b) => b.count - a.count)
      .slice(0, 10);

    // Location highlights
    const locationMap = {};
    for (const m of allMemories) {
      if (m.location?.name) {
        if (!locationMap[m.location.name]) {
          locationMap[m.location.name] = {
            name: m.location.name,
            count: 0,
            thumbnail: null,
          };
        }
        locationMap[m.location.name].count++;
        if (!locationMap[m.location.name].thumbnail) {
          const photo = m.mediaItems.find((i) => i.type === "photo");
          if (photo)
            locationMap[m.location.name].thumbnail = photo.cloudinaryUrl;
        }
      }
    }
    const places = Object.values(locationMap)
      .sort((a, b) => b.count - a.count)
      .slice(0, 10);

    // Stats
    const totalPhotos = allMemories.reduce(
      (sum, m) => sum + m.mediaItems.filter((i) => i.type === "photo").length,
      0,
    );
    const totalVideos = allMemories.reduce(
      (sum, m) => sum + m.mediaItems.filter((i) => i.type === "video").length,
      0,
    );

    // Featured memory — most recent with a title
    const featured =
      allMemories.find((m) => m.title && m.mediaItems.length > 0) || null;

    res.json({
      featured,
      weeklyRecap:
        recentMemories.length > 0
          ? {
              memoryCount: recentMemories.length,
              locations: weeklyLocations,
              moods: weeklyMoods,
              coverPhoto: weeklyCover,
              dateRange: {
                start: weekAgo.toISOString(),
                end: now.toISOString(),
              },
            }
          : null,
      monthlyRecap:
        monthlyMemories.length > 0
          ? {
              memoryCount: monthlyMemories.length,
              locations: monthlyLocations,
              coverPhoto: monthlyCover,
              dateRange: {
                start: monthAgo.toISOString(),
                end: now.toISOString(),
              },
            }
          : null,
      onThisDay,
      people,
      places,
      stats: {
        totalMemories: allMemories.length,
        totalPhotos,
        totalVideos,
        totalLocations: places.length,
      },
    });
  } catch (err) {
    console.error("Discover error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/ai/chat
 * Chat with AI about your memories
 */
router.post("/chat", async (req, res, next) => {
  try {
    if (!gemini.enabled) {
      return res
        .status(503)
        .json({ error: "AI features not configured. Set GEMINI_API_KEY." });
    }

    const { message } = req.body;
    if (!message || typeof message !== "string") {
      return res.status(400).json({ error: "message is required" });
    }

    // Get a summary of memories for context
    const memories = await Memory.find()
      .sort({ createdAt: -1 })
      .limit(50)
      .lean();

    const memorySummary = memories.map((m) => ({
      title: m.title,
      description: m.description,
      createdAt: m.createdAt,
      mediaCount: m.mediaItems.length,
    }));

    const reply = await gemini.chat(message, memorySummary);
    res.json({ reply });
  } catch (err) {
    console.error("AI chat error:", err.message);
    res.status(500).json({ error: err.message || "AI chat failed" });
  }
});

module.exports = router;
