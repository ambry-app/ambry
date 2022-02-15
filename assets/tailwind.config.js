const colors = require('tailwindcss/colors')

module.exports = {
  content: [
    './js/**/*.js',
    '../lib/*_web/**/*.*ex',
    '../lib/*_web/**/*.sface',
    '../deps/petal_components/**/*.*ex'
  ],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        gray: colors.zinc,
        primary: colors.lime,
        secondary: colors.zinc
      }
    }
  },
  plugins: [
    require('@tailwindcss/aspect-ratio'),
    require("@tailwindcss/forms")
  ]
}
