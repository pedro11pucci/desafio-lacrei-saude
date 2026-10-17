test("GET /status deve retornar 200", async () => {
  const response = await fetch("http://localhost/status");

  expect(response.status).toBe(200);
});