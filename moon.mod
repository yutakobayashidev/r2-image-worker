name = "yutakobayashidev/r2-image-worker"

version = "2.0.0"

import {
  "mizchi/cloudflare@0.1.9",
  "mizchi/js@0.10.14",
  "moonbitlang/async@0.16.6",
}

readme = "README.md"

repository = "https://github.com/yutakobayashidev/r2-image-worker"

license = "MIT"

keywords = [ "cloudflare", "workers", "r2", "images" ]

description = "Store and deliver images with Cloudflare R2 backend Cloudflare Workers."

preferred_target = "js"

options(
  source: "src",
)
