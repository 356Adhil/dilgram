const cloudinary = require("../config/cloudinary");
const streamifier = require("streamifier");

class CloudinaryService {
  /**
   * Upload a file buffer to Cloudinary
   * @param {Buffer} fileBuffer
   * @param {string} type - 'photo' or 'video'
   * @returns {Promise<Object>} Upload result
   */
  static async upload(fileBuffer, type) {
    return new Promise((resolve, reject) => {
      const resourceType = type === "video" ? "video" : "image";
      const folder = `dilgram/${type}s`;

      const uploadOptions = {
        resource_type: resourceType,
        folder,
        quality: "auto:best",
      };

      // For videos, generate a thumbnail asynchronously for faster response
      if (type === "video") {
        uploadOptions.eager = [
          { width: 400, height: 400, crop: "fill", format: "jpg" },
        ];
        uploadOptions.eager_async = true;
      }

      const uploadStream = cloudinary.uploader.upload_stream(
        uploadOptions,
        (error, result) => {
          if (error) {
            reject(error);
          } else {
            const response = {
              url: result.secure_url,
              publicId: result.public_id,
              width: result.width,
              height: result.height,
              size: result.bytes,
              format: result.format,
              resourceType: result.resource_type,
            };

            // Add duration for videos
            if (type === "video" && result.duration) {
              response.duration = result.duration;
            }

            // Add thumbnail URL for videos
            if (type === "video") {
              if (result.eager && result.eager[0]) {
                response.thumbnailUrl = result.eager[0].secure_url;
              } else {
                // Construct thumbnail URL from video URL (eager_async may not be ready)
                response.thumbnailUrl = result.secure_url
                  .replace(
                    "/video/upload/",
                    "/video/upload/w_400,h_400,c_fill/",
                  )
                  .replace(/\.\w+$/, ".jpg");
              }
            }

            resolve(response);
          }
        },
      );

      streamifier.createReadStream(fileBuffer).pipe(uploadStream);
    });
  }

  /**
   * Delete a file from Cloudinary
   * @param {string} publicId
   * @param {string} type - 'photo' or 'video'
   */
  static async delete(publicId, type) {
    const resourceType = type === "video" ? "video" : "image";
    return cloudinary.uploader.destroy(publicId, {
      resource_type: resourceType,
    });
  }

  /**
   * Delete multiple files
   * @param {Array<{publicId: string, type: string}>} items
   */
  static async deleteMany(items) {
    const promises = items.map((item) => this.delete(item.publicId, item.type));
    return Promise.allSettled(promises);
  }
}

module.exports = CloudinaryService;
