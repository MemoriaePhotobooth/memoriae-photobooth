const { initializeApp, cert } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

initializeApp({
  credential: cert(require("./serviceAccountKey.json")),
  projectId: "memoriae-photobooth-3897b"
});

const EMAIL = "admin@memoriae.com";
const PASSWORD = "Admin@2026!";

async function main() {
  const auth = getAuth();
  let user;
  try {
    user = await auth.getUserByEmail(EMAIL);
    console.log("Existing na ang user:", user.uid);
    await auth.updateUser(user.uid, { password: PASSWORD });
    console.log("Napalitan ang password.");
  } catch (e) {
    if (e.code === "auth/user-not-found") {
      user = await auth.createUser({ email: EMAIL, password: PASSWORD });
      console.log("Nagawa ang user:", user.uid);
    } else {
      throw e;
    }
  }

  await getFirestore().collection("admins").doc(user.uid).set({
    name: "Admin",
    email: EMAIL,
    active: true,
    createdAt: FieldValue.serverTimestamp()
  });
  console.log("Nagawa ang admins document. TAPOS NA!");
}

main().catch(e => { console.error(e.code, e.message); process.exit(1); });