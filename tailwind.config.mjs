import daisyui from "daisyui";

export default {
  content: [
    "./app/helpers/**/*.rb",
    "./app/javascript/**/*.{js,ts,jsx,tsx}",
    "./app/views/**/*.{erb,html,html+turbo_stream}"
  ],
  theme: {
    extend: {}
  },
  plugins: [daisyui],
  daisyui: {
    themes: ["light"]
  }
};

