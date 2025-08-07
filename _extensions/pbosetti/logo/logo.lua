return {
  ['logo'] = function(args, kwargs, meta, raw_args, context) 
    local file = args[1] or "logo.svg"
    local height = pandoc.utils.stringify(kwargs["height"])
    if height == "" then
      height = "0.9"
    end
    local offset = pandoc.utils.stringify(kwargs["offset"])
    if offset == "" then
      offset = "-0.125"
    end
    local folder = pandoc.utils.stringify(kwargs["folder"])
    if folder == "" then
      folder = "/images"
    end
    local shadow = pandoc.utils.stringify(kwargs["shadow"])
    if shadow == "" then
      shadow = "drop-shadow(2px 2px 2px rgba(0,0,0,0.2))"
    end
    
    local style = 'style="height: ' .. height .. 'em; vertical-align: ' .. offset .. 'em; margin: 0; padding: 0; filter: ' .. shadow .. ';"'
    return pandoc.RawBlock("html", '<img src="' .. folder .. '/' .. file .. '" ' .. style .. '>')
  end
}
