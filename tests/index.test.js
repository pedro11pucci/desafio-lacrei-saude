
const request = require("supertest");
const app = require("../src/index");

describe("API health check - GET /status", () => {
  const originalEnv = process.env.APP_ENV;

  afterEach(() => {
    if (originalEnv === undefined) {
      delete process.env.APP_ENV;
    } else {
      process.env.APP_ENV = originalEnv;
    }
  });

  test("deve retornar HTTP 200", async () => {
    const response = await request(app).get("/status");

    expect(response.status).toBe(200);
  });

  test("deve retornar um JSON com status ok", async () => {
    const response = await request(app).get("/status");

    expect(response.status).toBe(200);
    expect(response.headers["content-type"]).toMatch(/json/);
    expect(response.body).toHaveProperty("status", "ok");
  });

  test("deve retornar o ambiente staging", async () => {
    process.env.APP_ENV = "staging";

    const response = await request(app).get("/status");

    expect(response.status).toBe(200);
    expect(response.body.environment).toBe("staging");
    expect(response.body.status).toBe("ok");
  });

  test("deve retornar o ambiente production", async () => {
    process.env.APP_ENV = "production";

    const response = await request(app).get("/status");

    expect(response.status).toBe(200);
    expect(response.body.environment).toBe("production");
  });

  test("deve retornar 404 para uma rota inexistente", async () => {
    const response = await request(app).get("/rota-inexistente");

    expect(response.status).toBe(404);
  });

  test("não deve aceitar POST em /status", async () => {
    const response = await request(app).post("/status");

    expect(response.status).toBe(404);
  });
});
