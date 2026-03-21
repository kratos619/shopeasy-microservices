const express = require("express");
const mysql = require("mysql2/promise");

const app = express();
app.use(express.json());

let db;

async function connectDB() {
  db = await mysql.createConnection({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
  });

  await db.execute(`
    CREATE TABLE IF NOT EXISTS users (
      id INT AUTO_INCREMENT PRIMARY KEY,
      username VARCHAR(255) NOT NULL,
      email VARCHAR(255) NOT NULL UNIQUE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);

  console.log("Connected to MySQL");
}

// Health check
app.get("/health", (req, res) => {
  res.json({ status: "healthy", service: "user-service" });
});

// Register user
app.post("/register", async (req, res) => {
  const { username, email, password } = req.body;

  if (!username || !email || !password) {
    return res.status(400).json({ error: "Missing fields" });
  }

  try {
    const [result] = await db.execute(
      "INSERT INTO users (username, email) VALUES (?, ?)",
      [username, email],
    );
    res.status(201).json({ message: "User created", userId: result.insertId });
  } catch (err) {
    if (err.code === "ER_DUP_ENTRY") {
      return res.status(400).json({ error: "Email already exists" });
    }
    res.status(500).json({ error: "Database error" });
  }
});

// Get all users
app.get("/users", async (req, res) => {
  const [rows] = await db.execute(
    "SELECT id, username, email, created_at FROM users",
  );
  res.json({ users: rows });
});

// Get user by ID
app.get("/users/:id", async (req, res) => {
  const [rows] = await db.execute(
    "SELECT id, username, email, created_at FROM users WHERE id = ?",
    [req.params.id],
  );

  if (rows.length === 0) {
    return res.status(404).json({ error: "User not found" });
  }

  res.json({ user: rows[0] });
});

const PORT = process.env.PORT || 3001;

module.exports = app;

if (require.main === module) {
  connectDB()
    .then(() => {
      app.listen(PORT, () => {
        console.log(`User service running on port ${PORT}`);
      });
    })
    .catch((err) => {
      console.error("Failed to connect to DB:", err);
      process.exit(1);
    });
}
