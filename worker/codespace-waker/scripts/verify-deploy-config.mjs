import { readFile } from "node:fs/promises";

const configPath = new URL("../wrangler.toml", import.meta.url);
let source;
try {
  source = await readFile(configPath, "utf8");
} catch (error) {
  console.error("Missing worker/codespace-waker/wrangler.toml. Copy wrangler.toml.example and set CODESPACE_NAME before deploying.");
  process.exit(1);
}

const match = source.match(/^\s*CODESPACE_NAME\s*=\s*"([^"]+)"\s*$/m);
const codespaceName = match?.[1]?.trim() || "";
if (!codespaceName || codespaceName === "YOUR_CODESPACE_NAME") {
  console.error("wrangler.toml does not contain a real CODESPACE_NAME; deployment was stopped.");
  process.exit(1);
}
if (!/^[a-z0-9][a-z0-9-]*$/i.test(codespaceName)) {
  console.error(`Invalid CODESPACE_NAME in wrangler.toml: ${codespaceName}`);
  process.exit(1);
}

console.log(`Deploy target confirmed: ${codespaceName}`);
