// GET /v1/assets — returns the list of symbols the events API knows
// about. Mirrors the Flutter app's static asset catalog.

import { Router } from "express"

import { SUPPORTED_ASSETS } from "../data/assets.js"

export const assetsRouter = Router()

assetsRouter.get("/", (_req, res) => {
  res.json({
    count: SUPPORTED_ASSETS.length,
    assets: SUPPORTED_ASSETS,
  })
})
