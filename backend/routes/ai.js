const express = require("express");
const auth = require("../middleware/auth");
const Memory = require("../models/Memory");
const gemini = require("../services/geminiService");

const router = express.Router();

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
      return res.status(503).json({ error: "AI features not configured" });
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
    next(err);
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

    // "On This Day" — memories from this date in previous years
    const allMemories = await Memory.find().sort({ createdAt: -1 }).lean();

    const onThisDay = allMemories.filter((m) => {
      const d = new Date(m.createdAt);
      return (
        d.getDate() === today &&
        d.getMonth() === month &&
        d.getFullYear() !== now.getFullYear()
      );
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

    res.json({
      onThisDay,
      weeklyStory,
      recentCount: recentMemories.length,
      stats: { totalMemories, totalPhotos, totalVideos },
    });
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
      return res.status(503).json({ error: "AI features not configured" });
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
    next(err);
  }
});

module.exports = router;
