const request = require("supertest");
const app = require("../src/index");

test("GET /status deve retornar 200", async () => {
  const response = await request(app).get("/status");

  expect(response.status).toBe(200);
  expect(response.body.status).toBe("ok");
});