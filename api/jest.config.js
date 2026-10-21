/** @type {import('jest').Config} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  setupFiles: ["<rootDir>/tests/env.ts"],
  testMatch: ["<rootDir>/tests/**/*.test.ts"],
  testTimeout: 30000,
  maxWorkers: 1,
  clearMocks: true,
};
