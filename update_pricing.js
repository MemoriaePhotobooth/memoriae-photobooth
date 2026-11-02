// Ina-update ang description at features ng mga package at camera sa
// `pricing` collection. Hindi binabago ang price, unit, at photo.
//
// Gamit:
//   node update_pricing.js            -> dry run, ipapakita lang ang gagawin
//   node update_pricing.js --apply    -> isusulat talaga sa Firestore
//
// Kailangan ang serviceAccountKey.json sa parehong folder (gaya ng add.js).

const { initializeApp, cert } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

const APPLY = process.argv.includes("--apply");

initializeApp({
  credential: cert(require("./serviceAccountKey.json")),
  projectId: "memoriae-photobooth-3897b",
});

// Kapag itinugma ang pangalan, hindi pinapansin ang case, espasyo, gitling,
// at mga simbolo. Halimbawa: "STRIP-STANDEE PACKAGE" = "Strip Standee Package".
const norm = (s) => (s || "").toLowerCase().replace(/[^a-z0-9]/g, "");

const ITEMS = [
  // ---------------- Booth packages ----------------
  {
    match: "Full Standee Package",
    description: "Unlimited photos for 2 hours with a standee frame and instant soft copy.",
    features: [
      "4R print (3 shots, 1 copy)",
      "High-quality 4x6 prints",
      "Free custom layout",
      "Free use of props",
      "Instant soft copy",
      "On-site staff to assist",
      "Free 1 4R ref magnet (for client only)",
    ],
  },
  {
    match: "Full Magnet Package",
    description: "Unlimited photos for 2 hours with a ref magnet and instant soft copy.",
    features: [
      "4R print with ref magnet (3 shots, 1 copy)",
      "High-quality 4x6 prints",
      "Free custom layout",
      "Free use of props",
      "Instant soft copy",
      "On-site staff to assist",
      "Free 1 4R ref magnet (for client only)",
    ],
  },
  {
    match: "4R Package",
    description: "Unlimited photos for 2 hours with one 4R printout.",
    features: [
      "1 4R printout (3 shots, 1 copy)",
      "High-quality 4x6 prints",
      "Free custom layout",
      "Free use of props",
      "Instant soft copy",
      "On-site staff to assist",
      "Free 1 4R ref magnet (for client only)",
    ],
  },
  {
    match: "2 Strip Package",
    description: "Unlimited photos for 2 hours with 2 strip printouts.",
    features: [
      "2 strip printouts (3 shots, 2 copies)",
      "High-quality 4x6 prints",
      "Free custom layout",
      "Free use of props",
      "Instant soft copy",
      "On-site staff to assist",
      "Free 1 4R ref magnet (for client only)",
    ],
  },
  {
    match: "Strip Standee Package",
    aliases: ["Strip Stand Package"],
    description: "Unlimited photos for 2 hours with strips in a standee frame.",
    features: [
      "2 strips with standee frame (3 shots, 2 copies)",
      "High-quality 4x6 prints",
      "Free custom layout",
      "Free use of props",
      "Instant soft copy",
      "On-site staff to assist",
      "Free 1 4R ref magnet (for client only)",
    ],
  },
  {
    match: "Strip Magnet Package",
    description: "Unlimited photos for 2 hours with strips and a ref magnet.",
    features: [
      "2 strips with ref magnet (3 shots, 2 copies)",
      "High-quality 4x6 prints",
      "Free custom layout",
      "Free use of props",
      "Instant soft copy",
      "On-site staff to assist",
      "Free 1 4R ref magnet (for client only)",
    ],
  },

  // ---------------- Camera rentals ----------------
  {
    match: "Instax Mini Evo",
    description: "Instant film camera with clear case, strap, bag, and 32GB SD card included.",
    features: [
      "Rates: ₱249/day (2-4 days), ₱199/day (5-7 days), ₱199/day (8 days onwards)",
      "+₱50 for 1-day rental",
      "Clear camera case",
      "Camera strap",
      "Camera bag",
      "OTG card reader (Android/iOS)",
      "USB-C charger cable with adapter",
      "32GB SD card",
      "Add-ons: 10 films ₱500, 20 films ₱900",
    ],
  },
  {
    match: "Kodak PixPro FZ55",
    description: "Compact Full HD camera with 5x wide zoom, bag, and silicone case included.",
    features: [
      "Rates: ₱249/day (2-4 days), ₱199/day (5-7 days), ₱179/day (8 days onwards)",
      "+₱50 for 1-day rental",
      "Battery",
      "Wrist strap",
      "Camera bag",
      "OTG card reader",
      "16GB SD card",
      "Silicone case",
      "Charger cable with adapter",
    ],
  },
  {
    match: "Canon 600D",
    description: "DSLR camera with kit lens, battery, charger, and 32GB SD card included.",
    features: [
      "Rates: ₱449/day (2-4 days), ₱399/day (5-7 days), ₱349/day (8 days onwards)",
      "+₱50 for 1-day rental",
      "1 original battery",
      "1 original charger",
      "Kit lens",
      "Camera strap",
      "Camera bag",
      "Front lens cap",
      "OTG card reader (Android/iOS)",
      "32GB SD card",
    ],
  },
  {
    match: "Canon IXUS 285 HS",
    description: "Compact camera with 12x optical zoom, hard case, and tempered glass included.",
    features: [
      "Rates: ₱349/day (2-4 days), ₱299/day (5-7 days), ₱249/day (8 days onwards)",
      "+₱50 for 1-day rental",
      "Battery",
      "Wrist strap",
      "Camera bag",
      "OTG card reader",
      "32GB SD card",
      "Camera hard case",
      "Tempered glass",
      "Charger cable with adapter",
    ],
  },
];

async function main() {
  const db = getFirestore();
  const snap = await db.collection("pricing").get();
  const docs = snap.docs.map((d) => ({ id: d.id, name: d.data().name || "", category: d.data().category || "" }));

  console.log(APPLY ? "MODE: APPLY (isusulat sa Firestore)" : "MODE: DRY RUN (walang isusulat; idagdag ang --apply)");
  console.log("");

  const batch = db.batch();
  let updates = 0;
  const notFound = [];

  for (const item of ITEMS) {
    const keys = [item.match, ...(item.aliases || [])].map(norm);
    // Unang subukan ang eksaktong tugma, tapos ang "naglalaman" ng pangalan.
    const hit =
      docs.find((d) => keys.includes(norm(d.name))) ||
      docs.find((d) => keys.some((k) => norm(d.name).includes(k)));

    if (!hit || !hit.name) {
      notFound.push(item.match);
      continue;
    }

    console.log(`✔ ${hit.name}  (id: ${hit.id})`);
    console.log(`    description: ${item.description}`);
    console.log(`    features: ${item.features.length} na linya`);
    batch.set(db.collection("pricing").doc(hit.id), { description: item.description, features: item.features }, { merge: true });
    updates++;
  }

  console.log("");
  console.log(`Tutugmang items: ${updates} / ${ITEMS.length}`);
  if (notFound.length) {
    console.log("HINDI NAHANAP sa Firestore (tingnan ang eksaktong pangalan sa Admin > Pricing):");
    notFound.forEach((n) => console.log("  - " + n));
  }

  if (APPLY && updates > 0) {
    await batch.commit();
    console.log("\nTapos na. Na-update ang Firestore.");
  } else if (!APPLY) {
    console.log("\nWalang nabago. Patakbuhin ulit na may --apply kapag tama na ang lahat.");
  }
}

main().catch((e) => {
  console.error(e.code || "", e.message || e);
  process.exit(1);
});
