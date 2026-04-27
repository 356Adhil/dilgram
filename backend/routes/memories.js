const express = require("express");
const { body, query, validationResult } = require("express-validator");
const auth = require("../middleware/auth");
const upload = require("../middleware/upload");
const Memory = require("../models/Memory");
const CloudinaryService = require("../services/cloudinaryService");
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
 * GET /api/memories/grouped?by=location
 * Get memories grouped by location or month
 */
router.get("/grouped", async (req, res, next) => {
  try {
    const by = req.query.by || "location";
    const memories = await Memory.find().sort({ createdAt: -1 }).lean();

    if (by === "location") {
      const groups = {};
      for (const m of memories) {
        const key = m.location?.name || "Unknown Location";
        if (!groups[key]) {
          groups[key] = {
            name: key,
            lat: m.location?.lat || null,
            lng: m.location?.lng || null,
            memories: [],
          };
        }
        groups[key].memories.push(m);
      }
      const sorted = Object.values(groups).sort(
        (a, b) => b.memories.length - a.memories.length,
      );
      return res.json({ groups: sorted });
    }

    if (by === "month") {
      const groups = {};
      for (const m of memories) {
        const d = new Date(m.createdAt);
        const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
        const label = d.toLocaleString("en-US", {
          month: "long",
          year: "numeric",
        });
        if (!groups[key]) {
          groups[key] = { key, label, memories: [] };
        }
        groups[key].memories.push(m);
      }
      const sorted = Object.values(groups).sort((a, b) =>
        b.key.localeCompare(a.key),
      );
      return res.json({ groups: sorted });
    }

    // Default: by people
    if (by === "people") {
      const peopleMap = {};
      for (const m of memories) {
        if (m.people && m.people.length > 0) {
          for (const person of m.people) {
            const key = person.label || person.description || "Unknown";
            if (!peopleMap[key]) {
              peopleMap[key] = {
                label: key,
                description: person.description || null,
                count: 0,
                thumbnail: null,
                memories: [],
              };
            }
            peopleMap[key].count++;
            peopleMap[key].memories.push(m);
            if (!peopleMap[key].thumbnail) {
              const photo = m.mediaItems.find((i) => i.type === "photo");
              if (photo)
                peopleMap[key].thumbnail = faceCropUrl(photo.cloudinaryUrl);
            }
          }
        }
      }
      const sorted = Object.values(peopleMap).sort((a, b) => b.count - a.count);
      return res.json({ people: sorted });
    }

    res
      .status(400)
      .json({ error: "Invalid groupBy. Use: location, month, people" });
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
      // Fallback: regex search on tags, title, description, location name
      const regex = new RegExp(q, "i");
      memories = await Memory.find({
        $or: [
          { title: regex },
          { description: regex },
          { tags: regex },
          { "location.name": regex },
        ],
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
    const { title, description, latitude, longitude, locationName } = req.body;
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

    let aiTitle = null;
    let aiDescription = null;
    let aiTags = [];
    let aiMood = null;
    let aiPeople = [];

    // Auto-caption with Gemini (blocking so the response includes AI data)
    if (gemini.enabled) {
      const photoItem = mediaItems.find((item) => item.type === "photo");
      if (photoItem) {
        try {
          const analysis = await gemini.analyzeImage(photoItem.cloudinaryUrl);
          aiTags = analysis.tags || [];
          aiMood = analysis.mood || null;
          aiPeople = analysis.people || [];
          if (!title && analysis.title) aiTitle = analysis.title;
          if (!description && analysis.description)
            aiDescription = analysis.description;
        } catch (err) {
          console.error("Auto-caption failed:", err.message);
        }
      }
    }

    // Build location object if coordinates provided
    let location = null;
    if (latitude && longitude) {
      location = {
        lat: parseFloat(latitude),
        lng: parseFloat(longitude),
        name: locationName || null,
      };
      // Add location name to tags for searchability
      if (locationName) {
        const locParts = locationName
          .split(",")
          .map((s) => s.trim())
          .filter(Boolean);
        aiTags = [...new Set([...aiTags, ...locParts])];
      }
    }

    const memory = await Memory.create({
      title: title || aiTitle || null,
      description: description || aiDescription || null,
      tags: aiTags,
      mood: aiMood,
      location,
      people: aiPeople,
      mediaItems,
    });

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
