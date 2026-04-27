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
          const rawLabel = person.label || person.description || "Unknown";
          // Normalize: lowercase, trim, remove leading "a ", "the "
          const key = rawLabel
            .toLowerCase()
            .trim()
            .replace(/^(a |an |the )/, "");
          if (!peopleMap[key]) {
            peopleMap[key] = { label: rawLabel, count: 0, thumbnail: null };
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

      // Mood data for mood timeline (last 30 days)
      moodTimeline: (() => {
        const days = {};
        for (const m of monthlyMemories) {
          if (m.mood) {
            const dayKey = new Date(m.createdAt).toISOString().split("T")[0];
            if (!days[dayKey]) days[dayKey] = [];
            days[dayKey].push(m.mood);
          }
        }
        return Object.entries(days).map(([date, moods]) => ({
          date,
          moods,
          dominant: moods
            .sort(
              (a, b) =>
                moods.filter((v) => v === b).length -
                moods.filter((v) => v === a).length,
            )
            .at(0),
        }));
      })(),

      // Top colors across all memories
      colors: (() => {
        const colorCount = {};
        for (const m of allMemories) {
          if (m.colors && m.colors.length > 0) {
            for (const c of m.colors) {
              colorCount[c] = (colorCount[c] || 0) + 1;
            }
          }
        }
        return Object.entries(colorCount)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 12)
          .map(([hex, count]) => ({ hex, count }));
      })(),

      // Top vibes/aesthetics
      vibes: (() => {
        const vibeMap = {};
        for (const m of allMemories) {
          if (m.vibes && m.vibes.length > 0) {
            for (const v of m.vibes) {
              if (!vibeMap[v])
                vibeMap[v] = { name: v, count: 0, thumbnail: null };
              vibeMap[v].count++;
              if (!vibeMap[v].thumbnail) {
                const photo = m.mediaItems.find((i) => i.type === "photo");
                if (photo) vibeMap[v].thumbnail = photo.cloudinaryUrl;
              }
            }
          }
        }
        return Object.values(vibeMap)
          .sort((a, b) => b.count - a.count)
          .slice(0, 10);
      })(),

      // Has location data for map
      hasMapData:
        allMemories.filter((m) => m.location?.lat && m.location?.lng).length >
        0,
      mapPinCount: allMemories.filter((m) => m.location?.lat && m.location?.lng)
        .length,
    });
  } catch (err) {
    console.error("Discover error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/ai/journal?date=2026-04-27
 * Generate an AI diary entry for a specific date
 */
router.get("/journal", async (req, res, next) => {
  try {
    if (!gemini.enabled) {
      return res.status(503).json({ error: "AI features not configured" });
    }

    const dateStr = req.query.date;
    let targetDate;
    if (dateStr) {
      targetDate = new Date(dateStr + "T00:00:00.000Z");
    } else {
      targetDate = new Date();
      targetDate.setHours(0, 0, 0, 0);
    }

    const nextDay = new Date(targetDate);
    nextDay.setDate(nextDay.getDate() + 1);

    const memories = await Memory.find({
      createdAt: { $gte: targetDate, $lt: nextDay },
    })
      .sort({ createdAt: 1 })
      .lean();

    if (memories.length === 0) {
      return res.json({
        journal: null,
        message: "No memories found for this date",
      });
    }

    const journal = await gemini.generateJournalEntry(
      memories,
      targetDate.toLocaleDateString("en-US", {
        weekday: "long",
        year: "numeric",
        month: "long",
        day: "numeric",
      }),
    );

    const coverPhoto =
      memories.flatMap((m) => m.mediaItems).find((i) => i.type === "photo")
        ?.cloudinaryUrl || null;

    res.json({
      journal: {
        ...journal,
        date: targetDate.toISOString(),
        memoryCount: memories.length,
        coverPhoto,
        memories: memories.map((m) => ({
          id: m._id,
          title: m.title,
          thumbnail:
            m.mediaItems.find((i) => i.type === "photo")?.cloudinaryUrl || null,
        })),
      },
    });
  } catch (err) {
    console.error("Journal error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/ai/mashup
 * Generate an AI story from filtered memories
 * Body: { person?, place?, vibe?, dateFrom?, dateTo? }
 */
router.post("/mashup", async (req, res, next) => {
  try {
    if (!gemini.enabled) {
      return res.status(503).json({ error: "AI features not configured" });
    }

    const { person, place, vibe, dateFrom, dateTo } = req.body;

    let query = {};
    const filters = [];

    if (person) {
      query["people.label"] = { $regex: person, $options: "i" };
      filters.push(`person: "${person}"`);
    }
    if (place) {
      query["location.name"] = { $regex: place, $options: "i" };
      filters.push(`place: "${place}"`);
    }
    if (vibe) {
      query.vibes = { $regex: vibe, $options: "i" };
      filters.push(`vibe: "${vibe}"`);
    }
    if (dateFrom || dateTo) {
      query.createdAt = {};
      if (dateFrom) {
        query.createdAt.$gte = new Date(dateFrom);
        filters.push(`from: ${dateFrom}`);
      }
      if (dateTo) {
        query.createdAt.$lte = new Date(dateTo);
        filters.push(`to: ${dateTo}`);
      }
    }

    const memories = await Memory.find(query)
      .sort({ createdAt: -1 })
      .limit(30)
      .lean();

    if (memories.length === 0) {
      return res.json({
        mashup: null,
        message: "No matching memories found",
      });
    }

    const filterDescription =
      filters.length > 0 ? filters.join(", ") : "all memories";
    const mashup = await gemini.generateMashup(memories, filterDescription);

    const coverPhotos = memories
      .flatMap((m) => m.mediaItems)
      .filter((i) => i.type === "photo")
      .map((i) => i.cloudinaryUrl)
      .slice(0, 6);

    res.json({
      mashup: {
        ...mashup,
        memoryCount: memories.length,
        coverPhotos,
        memoryIds: memories.map((m) => m._id),
      },
    });
  } catch (err) {
    console.error("Mashup error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/ai/notifications
 * Get smart, AI-powered notification-worthy items
 */
router.get("/notifications", async (req, res, next) => {
  try {
    const now = new Date();
    const today = now.getDate();
    const month = now.getMonth();
    const allMemories = await Memory.find().sort({ createdAt: -1 }).lean();

    const notifications = [];

    // 1. On This Day — memories from this date in past years
    const onThisDayMemories = allMemories.filter((m) => {
      const d = new Date(m.createdAt);
      if (d.getFullYear() === now.getFullYear()) return false;
      return d.getDate() === today && d.getMonth() === month;
    });
    for (const m of onThisDayMemories.slice(0, 3)) {
      const yearsAgo = now.getFullYear() - new Date(m.createdAt).getFullYear();
      const photo = m.mediaItems.find((i) => i.type === "photo");
      notifications.push({
        type: "on_this_day",
        title: `${yearsAgo} year${yearsAgo > 1 ? "s" : ""} ago today`,
        body: m.title || "A moment worth remembering",
        memoryId: m._id.toString(),
        imageUrl: photo?.cloudinaryUrl || null,
        actionRoute: "/viewer",
      });
    }

    // 2. Streak milestone
    const daySet = new Set();
    for (const m of allMemories) {
      daySet.add(new Date(m.createdAt).toISOString().split("T")[0]);
    }
    let streak = 0;
    const d = new Date(now);
    while (daySet.has(d.toISOString().split("T")[0])) {
      streak++;
      d.setDate(d.getDate() - 1);
    }
    if (streak >= 3) {
      notifications.push({
        type: "streak",
        title: `🔥 ${streak}-day streak!`,
        body: `You've been capturing memories ${streak} days in a row. Keep going!`,
        memoryId: null,
        imageUrl: null,
        actionRoute: "/home",
      });
    }

    // 3. Weekly mood summary
    const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const weeklyMoods = allMemories
      .filter((m) => new Date(m.createdAt) >= weekAgo && m.mood)
      .map((m) => m.mood);
    if (weeklyMoods.length >= 3) {
      const moodFreq = {};
      weeklyMoods.forEach(
        (mood) => (moodFreq[mood] = (moodFreq[mood] || 0) + 1),
      );
      const dominant = Object.entries(moodFreq).sort((a, b) => b[1] - a[1])[0];
      if (dominant) {
        const moodEmojis = {
          joyful: "🌟",
          serene: "🧘",
          nostalgic: "💭",
          cozy: "☕",
          adventurous: "🌍",
          reflective: "🪞",
          energetic: "⚡",
          peaceful: "🕊️",
          romantic: "💕",
          melancholy: "🌧️",
        };
        const emoji = moodEmojis[dominant[0]] || "✨";
        notifications.push({
          type: "mood_summary",
          title: `${emoji} Your week was mostly ${dominant[0]}`,
          body: `Out of ${weeklyMoods.length} memories this week, the dominant mood was "${dominant[0]}". Beautiful!`,
          memoryId: null,
          imageUrl: null,
          actionRoute: "/mood-timeline",
        });
      }
    }

    // 4. Random nostalgia — a random older memory to resurface
    const olderMemories = allMemories.filter((m) => {
      const age = now.getTime() - new Date(m.createdAt).getTime();
      return age > 30 * 24 * 60 * 60 * 1000; // older than 1 month
    });
    if (olderMemories.length > 0) {
      const random =
        olderMemories[Math.floor(Math.random() * olderMemories.length)];
      const photo = random.mediaItems.find((i) => i.type === "photo");
      const timeAgo = Math.floor(
        (now.getTime() - new Date(random.createdAt).getTime()) /
          (24 * 60 * 60 * 1000),
      );
      notifications.push({
        type: "nostalgia",
        title: "✨ Remember this?",
        body:
          random.title || `A moment from ${timeAgo} days ago worth revisiting`,
        memoryId: random._id.toString(),
        imageUrl: photo?.cloudinaryUrl || null,
        actionRoute: "/viewer",
      });
    }

    // 5. Milestone counts
    const total = allMemories.length;
    const milestones = [10, 25, 50, 100, 200, 500, 1000];
    for (const m of milestones) {
      if (total >= m && total < m + 5) {
        notifications.push({
          type: "milestone",
          title: `🎉 ${m} memories!`,
          body: `You've captured ${total} memories. What a beautiful collection!`,
          memoryId: null,
          imageUrl: null,
          actionRoute: "/home",
        });
        break;
      }
    }

    // 6. Vibe trend
    const recentVibes = {};
    allMemories
      .filter((m) => new Date(m.createdAt) >= weekAgo)
      .forEach((m) => {
        (m.vibes || []).forEach(
          (v) => (recentVibes[v] = (recentVibes[v] || 0) + 1),
        );
      });
    const topVibe = Object.entries(recentVibes).sort((a, b) => b[1] - a[1])[0];
    if (topVibe && topVibe[1] >= 2) {
      notifications.push({
        type: "vibe_trend",
        title: `🎨 "${topVibe[0]}" vibes this week`,
        body: `Your recent photos have a strong "${topVibe[0]}" aesthetic. Love your style!`,
        memoryId: null,
        imageUrl: null,
        actionRoute: "/home",
      });
    }

    // 7. Color trend
    const recentColors = {};
    allMemories
      .filter((m) => new Date(m.createdAt) >= weekAgo)
      .forEach((m) => {
        (m.colors || []).forEach(
          (c) => (recentColors[c] = (recentColors[c] || 0) + 1),
        );
      });
    const topColor = Object.entries(recentColors).sort(
      (a, b) => b[1] - a[1],
    )[0];
    if (topColor && topColor[1] >= 2) {
      notifications.push({
        type: "color_trend",
        title: "🎨 Your color palette this week",
        body: `Your photos are painting a beautiful story with ${topColor[0]} tones`,
        memoryId: null,
        imageUrl: null,
        actionRoute: "/home",
      });
    }

    // 8. Capture prompt (if no memories today)
    const todayStr = now.toISOString().split("T")[0];
    const hasMemoryToday = allMemories.some(
      (m) => new Date(m.createdAt).toISOString().split("T")[0] === todayStr,
    );
    if (!hasMemoryToday && allMemories.length > 0) {
      const prompts = [
        "🌙 What moment made you smile today?",
        "📸 Capture something beautiful before the day ends",
        "✨ Every day has a moment worth remembering",
        "🌅 The best memories are the ones we almost forget to capture",
        "💫 Your future self will thank you for today's photo",
      ];
      notifications.push({
        type: "capture_prompt",
        title: prompts[Math.floor(Math.random() * prompts.length)],
        body: "Open the camera and save today's moment",
        memoryId: null,
        imageUrl: null,
        actionRoute: "/camera",
      });
    }

    res.json({ notifications });
  } catch (err) {
    console.error("Notifications error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/ai/mood-data
 * Get mood data for all memories (for mood timeline calendar)
 */
router.get("/mood-data", async (req, res, next) => {
  try {
    const memories = await Memory.find({ mood: { $exists: true, $ne: null } })
      .select("mood createdAt title")
      .sort({ createdAt: -1 })
      .lean();

    const dayMap = {};
    for (const m of memories) {
      const dayKey = new Date(m.createdAt).toISOString().split("T")[0];
      if (!dayMap[dayKey])
        dayMap[dayKey] = { date: dayKey, moods: [], memories: [] };
      dayMap[dayKey].moods.push(m.mood);
      dayMap[dayKey].memories.push({ id: m._id, title: m.title, mood: m.mood });
    }

    // Find dominant mood per day
    const days = Object.values(dayMap).map((d) => {
      const freq = {};
      d.moods.forEach((mood) => (freq[mood] = (freq[mood] || 0) + 1));
      const dominant = Object.entries(freq).sort((a, b) => b[1] - a[1])[0];
      return { ...d, dominant: dominant ? dominant[0] : null };
    });

    res.json({ days });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/ai/color-memories?hex=%23E8A87C
 * Get memories by dominant color
 */
router.get("/color-memories", async (req, res, next) => {
  try {
    const hex = req.query.hex;
    if (!hex) return res.status(400).json({ error: "hex parameter required" });

    const memories = await Memory.find({ colors: hex })
      .sort({ createdAt: -1 })
      .lean();

    res.json({ memories });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/ai/vibe-memories?vibe=golden%20hour
 * Get memories by vibe/aesthetic
 */
router.get("/vibe-memories", async (req, res, next) => {
  try {
    const vibe = req.query.vibe;
    if (!vibe)
      return res.status(400).json({ error: "vibe parameter required" });

    const memories = await Memory.find({
      vibes: { $regex: vibe, $options: "i" },
    })
      .sort({ createdAt: -1 })
      .lean();

    res.json({ memories });
  } catch (err) {
    next(err);
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
