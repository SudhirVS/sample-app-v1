const express = require("express");
const app = express();
const PORT = process.env.PORT || 3001;
const SERVICE = process.env.SERVICE_NAME || "order-service";
const NAMESPACE = process.env.NAMESPACE || "default";

const log = (msg) =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), service: SERVICE, namespace: NAMESPACE, message: msg }));

app.get("/health", (_, res) => res.json({ status: "ok" }));
app.get("/orders", (_, res) => {
  log("GET /orders called");
  res.json([{ id: 101, item: "Book", userId: 1 }, { id: 102, item: "Pen", userId: 2 }]);
});

app.listen(PORT, () => log(`${SERVICE} running on port ${PORT}`));
