// This file is synced from the `.github` repository, do not modify it directly.
import { defineConfig } from "@coderabbitai/config"

// Approved authors for this repository, populated by the shared configuration sync.
const autoApproveAuthors = new Set([])

export default defineConfig((ctx) => ({
  inheritance: true,

  reviews: {
    request_changes_workflow: autoApproveAuthors.has(ctx.pr?.author.toLowerCase() ?? ""),
  },
}))
