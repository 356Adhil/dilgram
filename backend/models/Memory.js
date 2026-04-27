const mongoose = require("mongoose");

const mediaItemSchema = new mongoose.Schema({
  type: {
    type: String,
    enum: ["photo", "video"],
    required: true,
  },
  cloudinaryUrl: {
    type: String,
    required: true,
  },
  cloudinaryPublicId: {
    type: String,
    required: true,
  },
  thumbnailUrl: String,
  width: Number,
  height: Number,
  duration: Number, // seconds, for video
  size: Number, // bytes
  mimeType: String,
  uploadedAt: {
    type: Date,
    default: Date.now,
  },
});

const memorySchema = new mongoose.Schema(
  {
    title: {
      type: String,
      trim: true,
      maxlength: 200,
    },
    description: {
      type: String,
      trim: true,
      maxlength: 2000,
    },
    mediaItems: [mediaItemSchema],
    tags: {
      type: [String],
      default: [],
    },
    mood: {
      type: String,
      trim: true,
    },
    isFavorite: {
      type: Boolean,
      default: false,
    },
    location: {
      lat: Number,
      lng: Number,
      name: String,
    },
    people: {
      type: [
        {
          label: { type: String, trim: true },
          description: { type: String, trim: true },
        },
      ],
      default: [],
    },
  },
  {
    timestamps: true,
  },
);

// Index for chronological listing
memorySchema.index({ createdAt: -1 });
// Text index for search
memorySchema.index({
  title: "text",
  description: "text",
  tags: "text",
  "location.name": "text",
});
// Index for favorites
memorySchema.index({ isFavorite: 1, createdAt: -1 });

module.exports = mongoose.model("Memory", memorySchema);
