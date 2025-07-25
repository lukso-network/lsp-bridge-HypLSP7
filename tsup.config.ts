import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["index.ts"],
  outDir: "dist",
  clean: true,
  dts: true, // Generate declaration files
  sourcemap: false,
  format: ["cjs", "esm"],
});
