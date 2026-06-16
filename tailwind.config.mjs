export default {
  content: [
    "./app/helpers/**/*.rb",
    "./app/components/**/*.{rb,erb}",
    "./app/javascript/**/*.{js,ts,jsx,tsx}",
    "./app/views/**/*.{erb,html,html+turbo_stream}",
    "./node_modules/flowbite/**/*.js"
  ],
  theme: {
    extend: {}
  },
  plugins: []
};
