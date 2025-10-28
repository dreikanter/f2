module.exports = {
  content: [
    "./app/helpers/**/*.rb",
    "./app/javascript/**/*.{js,ts,jsx,tsx}",
    "./app/views/**/*.{erb,html,html+turbo_stream}"
  ],
  theme: {
    extend: {}
  },
  plugins: [require("daisyui")],
  daisyui: {
    themes: ["light"]
  }
};

