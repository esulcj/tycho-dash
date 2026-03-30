#!/usr/bin/env node
// Seed script: uploads firms and quotes data to CF KV
// Usage: node seed.js
// Requires: wrangler configured with KV namespace

const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, "public", "data");

function upload(key, file) {
  const data = fs.readFileSync(file, "utf8");
  // Validate JSON
  JSON.parse(data);
  console.log(`Uploading ${key} from ${file} (${(data.length / 1024).toFixed(1)} KB)`);
  execSync(`npx wrangler kv:key put --binding=OUTREACH_KV "${key}" --path="${file}"`, {
    stdio: "inherit",
    cwd: __dirname,
  });
}

try {
  upload("firms", path.join(DATA_DIR, "firms_with_dossiers.json"));
  upload("quotes", path.join(DATA_DIR, "quotes-relevant-all.json"));
  console.log("Seed complete.");
} catch (err) {
  console.error("Seed failed:", err.message);
  process.exit(1);
}
