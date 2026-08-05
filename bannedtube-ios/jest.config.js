module.exports = {
  testEnvironment: "node",
  transform: {
    "^.+\\.tsx?$": [
      "ts-jest",
      {
        tsconfig: {
          strict: true,
          jsx: "react-jsx",
          esModuleInterop: true,
          moduleResolution: "node",
          types: ["jest"],
        },
      },
    ],
  },
  moduleFileExtensions: ["ts", "tsx", "js", "jsx", "json"],
  setupFiles: ["./jest.setup.js"],
  testPathIgnorePatterns: ["/node_modules/", "/build/"],
};
