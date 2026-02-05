const http = require("http");

const BASE_URL = "http://localhost:3001";

// Helper function to make requests
function request(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const options = {
      method,
      headers: { "Content-Type": "application/json" },
    };

    const req = http.request(`${BASE_URL}${path}`, options, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => {
        try {
          resolve({
            status: res.statusCode,
            body: JSON.parse(data),
          });
        } catch (e) {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });

    req.on("error", reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

// Test suite
async function runTests() {
  console.log("Starting tests...\n");
  let passed = 0;
  let failed = 0;

  // Test 1: Health check
  try {
    const res = await request("GET", "/health");
    if (res.status === 200 && res.body.status === "healthy") {
      console.log("✅ Test 1: Health check passed");
      passed++;
    } else {
      console.log("❌ Test 1: Health check failed");
      failed++;
    }
  } catch (e) {
    console.log("❌ Test 1: Health check failed -", e.message);
    failed++;
  }

  // Test 2: Register user
  try {
    const res = await request("POST", "/register", {
      username: "testuser",
      email: "test@example.com",
      password: "password123",
    });
    if (res.status === 201 && res.body.user) {
      console.log("✅ Test 2: User registration passed");
      passed++;
    } else {
      console.log("❌ Test 2: User registration failed");
      failed++;
    }
  } catch (e) {
    console.log("❌ Test 2: User registration failed -", e.message);
    failed++;
  }

  // Test 3: Get users
  try {
    const res = await request("GET", "/users");
    if (res.status === 200 && res.body.users) {
      console.log("✅ Test 3: Get users passed");
      passed++;
    } else {
      console.log("❌ Test 3: Get users failed");
      failed++;
    }
  } catch (e) {
    console.log("❌ Test 3: Get users failed -", e.message);
    failed++;
  }

  // Summary
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

// Start server and run tests
const app = require("./index");
const server = app.listen(3001, () => {
  console.log("Test server started on port 3001\n");
  setTimeout(() => {
    runTests().then(() => server.close());
  }, 500);
});
