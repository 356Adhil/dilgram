const express = require("express");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const { body, validationResult } = require("express-validator");
const AppConfig = require("../models/AppConfig");

const router = express.Router();

/**
 * POST /api/auth/setup-pin
 * First-time PIN setup (or re-setup)
 */
router.post(
  "/setup-pin",
  [body("pin").isLength({ min: 4, max: 6 }).isNumeric()],
  async (req, res, next) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ error: "PIN must be 4-6 digits" });
      }

      const { pin } = req.body;
      const salt = await bcrypt.genSalt(12);
      const hash = await bcrypt.hash(pin, salt);

      // Store in MongoDB (upsert)
      await AppConfig.findOneAndUpdate(
        { key: "pin_hash" },
        { key: "pin_hash", value: hash },
        { upsert: true, new: true },
      );

      const token = jwt.sign(
        { user: "dilgram_user", iat: Math.floor(Date.now() / 1000) },
        process.env.JWT_SECRET,
        { expiresIn: "30d" },
      );

      res.json({ message: "PIN set successfully", token });
    } catch (err) {
      next(err);
    }
  },
);

/**
 * POST /api/auth/verify-pin
 * Verify PIN and return JWT
 */
router.post(
  "/verify-pin",
  [body("pin").isLength({ min: 4, max: 6 }).isNumeric()],
  async (req, res, next) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ error: "PIN must be 4-6 digits" });
      }

      const config = await AppConfig.findOne({ key: "pin_hash" });
      if (!config) {
        return res.status(400).json({ error: "PIN not set up yet" });
      }

      const { pin } = req.body;
      const isValid = await bcrypt.compare(pin, config.value);

      if (!isValid) {
        return res.status(401).json({ error: "Invalid PIN" });
      }

      const token = jwt.sign(
        { user: "dilgram_user", iat: Math.floor(Date.now() / 1000) },
        process.env.JWT_SECRET,
        { expiresIn: "30d" },
      );

      res.json({ message: "PIN verified", token });
    } catch (err) {
      next(err);
    }
  },
);

module.exports = router;
