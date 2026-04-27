const express = require("express");
const { body, query, validationResult } = require("express-validator");
const auth = require("../middleware/auth");
const upload = require("../middleware/upload");
const Memory = require("../models/Memory");
const CloudinaryService = require("../services/cloudinaryService");
const gemini = require("../services/geminiService");

const router = express.Router();

// All routes require authentication
router.use(auth);

/**
 * GET /api/memories
 * List memories with pagination (newest first)
 */
router.get(
  "/",
  [
    query("page").optional().isInt({ min: 1 }),
    query("limit").optional().isInt({ min: 1, max: 50 }),
  ],
  async (req, res, next) => {
    try {
      const page = parseInt(req.query.page) || 1;
      const limit = parseInt(req.query.limit) || 20;
      const skip = (page - 1) * limit;

      const [memories, total] = await Promise.all([
        Memory.find().sort({ createdAt: -1 }).skip(skip).limit(limit).lean(),
        Memory.countDocuments(),
      ]);

      res.json({
        memories,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit),
        },
      });
    } catch (err) {
      next(err);
    }
  },
);

/**
 * GET /api/memories/stats
 * Get memory statistics
 */
router.get("/stats", async (req, res, next) => {
  try {
    const memories = await Memory.find().lean();

    let totalPhotos = 0;
    let totalVideos = 0;
    let totalSizeBytes = 0;

    for (const memory of memories) {
      for (const item of memory.mediaItems) {
        if (item.type === "photo") totalPhotos++;
        if (item.type === "video") totalVideos++;
        if (item.size) totalSizeBytes += item.size;
      }
    }

    res.json({
      totalMemories: memories.length,
      totalPhotos,
      totalVideos,
      totalSizeBytes,
    });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/memories/search?q=food
 * Search memories by title, description, tags
 */
router.get("/search", async (req, res, next) => {
  try {
    const q = (req.query.q || "").trim();
    if (!q) {
      return res.json({ memories: [] });
    }

    // Try text search first, fallback to regex
    let memories;
    try {
      memories = await Memory.find(
        { $text: { $search: q } },
        { score: { $meta: "textScore" } },
      )
        .sort({ score: { $meta: "textScore" } })
        .limit(50)
        .lean();
    } catch (e) {
      // Fallback: regex search on tags, title, description
      const regex = new RegExp(q, "i");
      memories = await Memory.find({
        $or: [{ title: regex }, { description: regex }, { tags: regex }],
      })
        .sort({ createdAt: -1 })
        .limit(50)
        .lean();
    }

    res.json({ memories });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/memories/favorites
 * List favorite memories
 */
router.get("/favorites", async (req, res, next) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 50;
    const skip = (page - 1) * limit;

    const memories = await Memory.find({ isFavorite: true })
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .lean();

    res.json({ memories });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/memories/batch-delete
 * Delete multiple memories at once
 */
router.post("/batch-delete", async (req, res, next) => {
  try {
    const { ids } = req.body;
    if (!Array.isArray(ids) || ids.length === 0) {
      return res.status(400).json({ error: "ids array is required" });
    }

    if (ids.length > 50) {
      return res.status(400).json({ error: "Max 50 memories per batch" });
    }

    const memories = await Memory.find({ _id: { $in: ids } });

    // Collect all Cloudinary items to delete
    const cloudinaryItems = [];
    for (const memory of memories) {
      for (const item of memory.mediaItems) {
        cloudinaryItems.push({
          publicId: item.cloudinaryPublicId,
          type: item.type,
        });
      }
    }

    // Delete from Cloudinary
    if (cloudinaryItems.length > 0) {
      await CloudinaryService.deleteMany(cloudinaryItems);
    }

    // Delete from DB
    await Memory.deleteMany({ _id: { $in: ids } });

    res.json({ deleted: ids.length });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/memories/:id
 * Get single memory
 */
router.get("/:id", async (req, res, next) => {
  try {
    const memory = await Memory.findById(req.params.id).lean();
    if (!memory) {
      return res.status(404).json({ error: "Memory not found" });
    }
    res.json(memory);
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/memories
 * Create memory with media upload
 */
router.post("/", upload.array("media", 10), async (req, res, next) => {
  try {
    const { title, description } = req.body;
    const files = req.files;
    const types = req.body.types; // array of 'photo' or 'video'

    if (!files || files.length === 0) {
      return res
        .status(400)
        .json({ error: "At least one media file is required" });
    }

    // Determine types for each file
    const fileTypes = Array.isArray(types) ? types : [types];

    // Upload all files to Cloudinary
    const uploadPromises = files.map((file, index) => {
      const type = fileTypes[index] || _inferType(file.mimetype);
      return CloudinaryService.upload(file.buffer, type).then((result) => ({
        ...result,
        type,
        mimeType: file.mimetype,
      }));
    });

    const uploadResults = await Promise.all(uploadPromises);

    // Create memory document
    const mediaItems = uploadResults.map((result) => ({
      type: result.type,
      cloudinaryUrl: result.url,
      cloudinaryPublicId: result.publicId,
      thumbnailUrl: result.thumbnailUrl || null,
      width: result.width,
      height: result.height,
      duration: result.duration || null,
      size: result.size,
      mimeType: result.mimeType,
    }));

    const memory = await Memory.create({
      title: title || null,
      description: description || null,
      mediaItems,
    });

    // Auto-tag with Gemini in background (non-blocking)
    if (gemini.enabled) {
      const photoItem = mediaItems.find((item) => item.type === "photo");
      if (photoItem) {
        gemini
          .analyzeImage(photoItem.cloudinaryUrl)
          .then(async (analysis) => {
            const updates = { tags: analysis.tags || [] };
            if (analysis.mood) updates.mood = analysis.mood;
            if (!title && analysis.title) updates.title = analysis.title;
            if (!description && analysis.description)
              updates.description = analysis.description;
            await Memory.findByIdAndUpdate(memory._id, { $set: updates });
          })
          .catch((err) => {
            console.error("Auto-tag failed:", err.message);
          });
      }
    }

    res.status(201).json({ memory });
  } catch (err) {
    next(err);
  }
});

/**
 * PUT /api/memories/:id
 * Update memory metadata
 */
router.put(
  "/:id",
  [
    body("title").optional().isString().trim().isLength({ max: 200 }),
    body("description").optional().isString().trim().isLength({ max: 2000 }),
  ],
  async (req, res, next) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ errors: errors.array() });
      }

      const updates = {};
      if (req.body.title !== undefined) updates.title = req.body.title;
      if (req.body.description !== undefined)
        updates.description = req.body.description;
      if (req.body.tags !== undefined) updates.tags = req.body.tags;
      if (req.body.mood !== undefined) updates.mood = req.body.mood;
      if (req.body.location !== undefined) updates.location = req.body.location;

      const memory = await Memory.findByIdAndUpdate(
        req.params.id,
        { $set: updates },
        { new: true, runValidators: true },
      );

      if (!memory) {
        return res.status(404).json({ error: "Memory not found" });
      }

      res.json({ memory });
    } catch (err) {
      next(err);
    }
  },
);

/**
 * PATCH /api/memories/:id/favorite
 * Toggle favorite status
 */
router.patch("/:id/favorite", async (req, res, next) => {
  try {
    const memory = await Memory.findById(req.params.id);
    if (!memory) {
      return res.status(404).json({ error: "Memory not found" });
    }

    memory.isFavorite = !memory.isFavorite;
    await memory.save();

    res.json({ isFavorite: memory.isFavorite });
  } catch (err) {
    next(err);
  }
});

/**
 * DELETE /api/memories/:id
 * Delete memory and cleanup Cloudinary files
 */
router.delete("/:id", async (req, res, next) => {
  try {
    const memory = await Memory.findById(req.params.id);
    if (!memory) {
      return res.status(404).json({ error: "Memory not found" });
    }

    // Delete all media from Cloudinary
    if (memory.mediaItems.length > 0) {
      const items = memory.mediaItems.map((item) => ({
        publicId: item.cloudinaryPublicId,
        type: item.type,
      }));
      await CloudinaryService.deleteMany(items);
    }

    await Memory.findByIdAndDelete(req.params.id);

    res.json({ message: "Memory deleted successfully" });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/memories/:id/media
 * Add media to existing memory
 */
router.post("/:id/media", upload.array("media", 10), async (req, res, next) => {
  try {
    const memory = await Memory.findById(req.params.id);
    if (!memory) {
      return res.status(404).json({ error: "Memory not found" });
    }

    const files = req.files;
    const types = req.body.types;

    if (!files || files.length === 0) {
      return res
        .status(400)
        .json({ error: "At least one media file is required" });
    }

    const fileTypes = Array.isArray(types) ? types : [types];

    const uploadPromises = files.map((file, index) => {
      const type = fileTypes[index] || _inferType(file.mimetype);
      return CloudinaryService.upload(file.buffer, type).then((result) => ({
        ...result,
        type,
        mimeType: file.mimetype,
      }));
    });

    const uploadResults = await Promise.all(uploadPromises);

    const newMediaItems = uploadResults.map((result) => ({
      type: result.type,
      cloudinaryUrl: result.url,
      cloudinaryPublicId: result.publicId,
      thumbnailUrl: result.thumbnailUrl || null,
      width: result.width,
      height: result.height,
      duration: result.duration || null,
      size: result.size,
      mimeType: result.mimeType,
    }));

    memory.mediaItems.push(...newMediaItems);
    await memory.save();

    res.json({ memory });
  } catch (err) {
    next(err);
  }
});

/**
 * DELETE /api/memories/:memoryId/media/:mediaId
 * Remove single media item from memory
 */
router.delete("/:memoryId/media/:mediaId", async (req, res, next) => {
  try {
    const memory = await Memory.findById(req.params.memoryId);
    if (!memory) {
      return res.status(404).json({ error: "Memory not found" });
    }

    const mediaItem = memory.mediaItems.id(req.params.mediaId);
    if (!mediaItem) {
      return res.status(404).json({ error: "Media item not found" });
    }

    // Delete from Cloudinary
    await CloudinaryService.delete(
      mediaItem.cloudinaryPublicId,
      mediaItem.type,
    );

    // Remove from memory
    memory.mediaItems.pull(req.params.mediaId);

    // If no media left, delete the memory
    if (memory.mediaItems.length === 0) {
      await Memory.findByIdAndDelete(req.params.memoryId);
      return res.json({ message: "Memory deleted (no media remaining)" });
    }

    await memory.save();
    res.json({ memory });
  } catch (err) {
    next(err);
  }
});

/**
 * Infer media type from MIME type
 */
function _inferType(mimeType) {
  if (mimeType && mimeType.startsWith("video/")) return "video";
  return "photo";
}

module.exports = router;
