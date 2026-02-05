const express = require("express");
const app = express();

app.use(express.json());

// In-memory users (we'll add MySQL later)
const users = [];

// Health check
app.get("/health", (req, res) => {
  res.json({ status: "healthy", service: "user-service" });
});

// Register user
app.post("/register", (req, res) => {
  const { username, email, password } = req.body;

  if (!username || !email || !password) {
    return res.status(400).json({ error: "Missing fields" });
  }

  const user = {
    id: users.length + 1,
    username,
    email,
    createdAt: new Date(),
  };

  users.push(user);
  res.status(201).json({ message: "User created", user });
});

// Get all users
app.get("/users", (req, res) => {
  res.json({ users });
});

// Get user by ID
app.get("/users/:id", (req, res) => {
  const user = users.find((u) => u.id === parseInt(req.params.id));

  if (!user) {
    return res.status(404).json({ error: "User not found" });
  }

  res.json({ user });
});

const PORT = process.env.PORT || 3001;

// Export the app for testing
module.exports = app;

// Only start server if this file is run directly (not required by tests)
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`User service running on port ${PORT}`);
  });
}