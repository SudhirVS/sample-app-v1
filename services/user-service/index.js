const express = require("express");
const app = express();
const PORT = process.env.PORT || 3000;
const SERVICE = process.env.SERVICE_NAME || "user-service";
const NAMESPACE = process.env.NAMESPACE || "default";

const log = (msg) =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), service: SERVICE, namespace: NAMESPACE, message: msg }));

app.get("/health", (_, res) => res.json({ status: "ok" }));
app.get("/users", (_, res) => {
  log("GET /users called");
  res.json([{ id: 1, name: "Alice" }, { id: 2, name: "Bob" }]);
});

app.listen(PORT, () => log(`${SERVICE} running on port ${PORT}`));
