import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

export default defineConfig(async () => {
  const migrations = await readD1Migrations("./migrations");
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.jsonc" },
        miniflare: { bindings: { MIGRATIONS: migrations, APNS_KEY: "", APNS_KEY_ID: "k", APNS_TEAM_ID: "t" } },
      }),
    ],
    test: { setupFiles: ["./test/setup.ts"] },
  };
});
