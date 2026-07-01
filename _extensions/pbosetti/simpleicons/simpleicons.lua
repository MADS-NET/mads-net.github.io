local function isEmpty(s)
  return s == nil or s == ''
end

local str = pandoc.utils.stringify

return {
  ["si"] = function(args, kwargs)
    local slug = str(args[1])
    local size = str(kwargs["size"])
    local color = str(kwargs["color"])
    local label = str(kwargs["label"])
    local class = str(kwargs["class"])

    if quarto.doc.isFormat("html:js") then
      -- Fetch SVG from Simple Icons CDN
      local url = "https://simpleicons.org/icons/" .. slug .. ".svg"
      local mt, content = pandoc.mediabag.fetch(url)

      if not content or content == "" then
        -- Fallback to an img tag if fetch fails (e.g. offline)
        return pandoc.RawInline(
          'html',
          string.format('<img src="%s" alt="%s" />', url, slug)
        )
      end

      -- Strip XML declaration if present
      content = content:gsub("^%s*<%?xml.-%?>%s*", "")

      -- Build inline style
      local styles = { "display:inline-block", "vertical-align:-0.125em" }
      if not isEmpty(size) then
        table.insert(styles, "height:" .. size)
        table.insert(styles, "width:" .. size)
      else
        table.insert(styles, "height:1em")
        table.insert(styles, "width:1em")
      end
      if not isEmpty(color) then
        table.insert(styles, "fill:" .. color)
      end
      local style_str = table.concat(styles, ";")

      -- Build extra class string
      local extra_class = ""
      if not isEmpty(class) then
        extra_class = " " .. class
      end

      -- Inject attributes into the opening <svg> tag.
      -- Use a replacement function so % in attribute values is never misinterpreted.
      if not isEmpty(label) then
        -- Replace existing <title> with user-supplied label
        content = content:gsub(
          "<title>[^<]*</title>",
          function() return "<title>" .. label .. "</title>" end,
          1
        )
        content = content:gsub(
          "<svg ",
          function()
            return string.format(
              '<svg style="%s" class="si si-%s%s" ',
              style_str, slug, extra_class
            )
          end,
          1
        )
      else
        -- No label: mark as decorative
        content = content:gsub(
          "<svg ",
          function()
            return string.format(
              '<svg style="%s" class="si si-%s%s" aria-hidden="true" ',
              style_str, slug, extra_class
            )
          end,
          1
        )
      end

      return pandoc.RawInline('html', content)
    else
      return pandoc.Null()
    end
  end
}
