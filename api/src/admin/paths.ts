import fs from "fs";
import path from "path";

const candidates = [
  process.cwd(),
  path.resolve(__dirname, "../../.."),
  path.resolve(__dirname, "../.."),
];

export const apiRoot =
  candidates.find((candidate) => fs.existsSync(path.join(candidate, "views", "admin"))) ??
  process.cwd();

export const viewsDir = path.join(apiRoot, "views");
export const adminAssetsDir = path.join(apiRoot, "public", "admin");
