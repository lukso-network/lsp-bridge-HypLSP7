import { ContractConfig, defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";
import { existsSync, readdirSync, readFileSync } from "fs";

const contracts: ContractConfig<number, undefined>[] = [];
if (existsSync("artifacts")) {
  readdirSync("artifacts").forEach((artifactName) => {
    const name = artifactName.replace(".json", "");
    const { abi } = JSON.parse(readFileSync(`artifacts/${artifactName}`).toString());

    contracts.push({
      abi,
      name,
    });
  });
} else {
  throw new Error("Missing artifacts in `/artifacts`");
}

export default defineConfig({
  out: "abi.ts",
  contracts,
  plugins: [
    foundry({
      artifacts: "artifacts/",
    }),
  ],
});
