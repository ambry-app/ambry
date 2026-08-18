// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: ["./js/**/*.js", "../lib/*_web.ex", "../lib/*_web/**/*.*ex"],
  // The app is dark-only: every color class is absolute and no dark: variants
  // exist. The "class" strategy (with no .dark anywhere) makes any dark:
  // class that sneaks back in a visible no-op rather than an OS-dependent one.
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: "#84cc16",
          dark: "#a3e635",
        },
      },
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    require("@tailwindcss/aspect-ratio"),
    require("@tailwindcss/typography"),
    plugin(({ addVariant }) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({ addVariant }) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({ addVariant }) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),
    // FontAwesome Free icons, vendored as SVGs and rendered as CSS masks.
    // Generates `fa-<name>` (solid) and `fa-brands-<name>` classes. Colored by the
    // current text color; sized 1.5rem by default (override with h-*/w-* utilities).
    plugin(function ({ matchComponents, theme }) {
      const iconsDir = path.join(__dirname, "vendor/fontawesome")
      const groups = [
        ["fa", "solid"],
        ["fa-brands", "brands"],
      ]

      groups.forEach(([prefix, dir]) => {
        const fullDir = path.join(iconsDir, dir)
        const values = {}

        fs.readdirSync(fullDir).forEach((file) => {
          const name = path.basename(file, ".svg")
          values[name] = { name, fullPath: path.join(fullDir, file) }
        })

        matchComponents(
          {
            [prefix]: ({ name, fullPath }) => {
              const content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
              const url = `url('data:image/svg+xml;utf8,${encodeURIComponent(content)}')`
              const size = theme("spacing.6")

              return {
                [`--fa-${name}`]: url,
                "-webkit-mask": `var(--fa-${name})`,
                mask: `var(--fa-${name})`,
                "mask-repeat": "no-repeat",
                "mask-position": "center",
                "mask-size": "contain",
                "background-color": "currentColor",
                "vertical-align": "middle",
                display: "inline-block",
                width: size,
                height: size,
              }
            },
          },
          { values },
        )
      })
    }),
  ],
}
