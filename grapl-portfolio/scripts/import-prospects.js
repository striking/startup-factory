const fs = require("node:fs");
const path = require("node:path");
const { parse } = require("csv-parse/sync");

const BATCH_SIZE = 500;

function usage() {
  return "Usage: node scripts/import-prospects.js /absolute/or/relative/path/to.csv";
}

function asOptionalTrimmed(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function parseNumber(value) {
  const trimmed = asOptionalTrimmed(value);
  if (!trimmed) return null;
  const num = Number.parseFloat(trimmed);
  return Number.isFinite(num) ? num : null;
}

function parseInteger(value) {
  const trimmed = asOptionalTrimmed(value);
  if (!trimmed) return null;
  const num = Number.parseInt(trimmed, 10);
  return Number.isFinite(num) ? num : null;
}

function resolveSupabaseConfig() {
  const url = process.env.SUPABASE_URL?.trim();
  if (!url) {
    throw new Error("Missing SUPABASE_URL environment variable.");
  }

  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (serviceRoleKey) {
    return { url, key: serviceRoleKey };
  }

  const anonKey = process.env.SUPABASE_ANON_KEY?.trim();
  if (anonKey) {
    return { url, key: anonKey };
  }

  throw new Error(
    "Missing SUPABASE_SERVICE_ROLE_KEY (or SUPABASE_ANON_KEY fallback) environment variable.",
  );
}

async function main() {
  const inputPath = process.argv[2];
  if (!inputPath) {
    console.error(usage());
    process.exitCode = 1;
    return;
  }

  const resolvedPath = path.resolve(process.cwd(), inputPath);
  if (!fs.existsSync(resolvedPath)) {
    console.error(`CSV not found: ${resolvedPath}`);
    process.exitCode = 1;
    return;
  }

  const csvContents = fs.readFileSync(resolvedPath, "utf8");
  const records = parse(csvContents, {
    columns: true,
    skip_empty_lines: true,
    trim: true,
  });

  const { createClient } = await import("@supabase/supabase-js");
  const config = resolveSupabaseConfig();
  const supabase = createClient(config.url, config.key, {
    auth: { persistSession: false },
  });

  const sourceRef = path.basename(resolvedPath);

  let total = records.length;
  let skipped = 0;
  let errors = 0;
  let upserted = 0;

  const rows = [];

  for (const row of records) {
    const placeId = asOptionalTrimmed(row.place_id);
    if (!placeId) {
      skipped += 1;
      continue;
    }

    const name = asOptionalTrimmed(row.business_name);
    if (!name) {
      errors += 1;
      continue;
    }

    rows.push({
      name,
      category: asOptionalTrimmed(row.trade_category),
      city_search: asOptionalTrimmed(row.city_search),
      formatted_address: asOptionalTrimmed(row.formatted_address),
      phone: asOptionalTrimmed(row.phone),
      website: asOptionalTrimmed(row.website),
      google_maps_url: asOptionalTrimmed(row.google_maps_url),
      place_id: placeId,
      rating: parseNumber(row.rating),
      review_count: parseInteger(row.review_count),
      source: "quotefollow",
      source_ref: sourceRef,
    });
  }

  for (let i = 0; i < rows.length; i += BATCH_SIZE) {
    const batch = rows.slice(i, i + BATCH_SIZE);
    try {
      const { error } = await supabase
        .from("prospects")
        .upsert(batch, { onConflict: "place_id" });

      if (error) {
        console.error(`Batch ${i / BATCH_SIZE + 1} failed: ${error.message}`);
        errors += batch.length;
      } else {
        upserted += batch.length;
      }
    } catch (err) {
      console.error(
        `Batch ${i / BATCH_SIZE + 1} crashed: ${err instanceof Error ? err.message : String(err)}`,
      );
      errors += batch.length;
    }
  }

  console.log(
    JSON.stringify(
      {
        total,
        skipped,
        upserted,
        errors,
      },
      null,
      2,
    ),
  );

  if (errors > 0) {
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : String(err));
  process.exitCode = 1;
});
