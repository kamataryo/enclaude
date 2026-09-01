// claude --settings は 1 ファイルしか取れないので、起動前にここで重ねて 1 つにする。
// 引数は後ろほど強い。オブジェクトは再帰的にマージし、配列やプリミティブは丸ごと上書きする。
import { readFileSync } from "node:fs";

const load = (path) => {
  let text;
  try {
    text = readFileSync(path, "utf8").trim();
  } catch {
    return {}; // マウントされていなければ無いものとして扱う
  }
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch (e) {
    // 壊れた override で起動できなくなるより、警告して素通りさせる
    console.error(`enclaudé: ${path} を JSON として読めませんでした（${e.message}）。無視します`);
    return {};
  }
};

const isPlainObject = (value) =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const merge = (base, override) => {
  const merged = { ...base };
  for (const [key, value] of Object.entries(override)) {
    merged[key] =
      isPlainObject(value) && isPlainObject(base[key]) ? merge(base[key], value) : value;
  }
  return merged;
};

const settings = process.argv.slice(2).map(load).reduce(merge, {});
process.stdout.write(`${JSON.stringify(settings, null, 2)}\n`);
