const colors = require('tailwindcss/colors')

module.exports = {
  content: [
    './js/**/*.js',
    '../lib/*_web/**/*.*ex',
    '../lib/*_web/**/*.sface',
    '../deps/petal_components/**/*.*ex'
  ],
  theme: {
    extend: {
      colors: {
        gray: colors.zinc,
        primary: colors.lime,
        secondary: colors.zinc
      }
    },
    // fix mobile browser viewport height shenanigans.
    // https://www.markusantonwolf.com/blog/solution-to-the-mobile-viewport-height-issue-with-tailwind-css/
    // see root.html.heex for other half
    height: theme => ({
      auto: 'auto',
      ...theme('spacing'),
      full: '100%',
      screen: 'calc(var(--vh) * 100)',
    }),
    minHeight: theme => ({
      '0': '0',
      ...theme('spacing'),
      full: '100%',
      screen: 'calc(var(--vh) * 100)',
    })
    // end viewport fix
  },
  plugins: [
    require('@tailwindcss/aspect-ratio'),
    require('@tailwindcss/forms')
  ]
}
