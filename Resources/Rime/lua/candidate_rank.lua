-- Rank a bounded prefix; never materialize the whole candidate dictionary.
-- The Chinese translator supplies original dictionary spelling in comment.
local M = {}
local function compact(text)
  return (text or ""):lower():gsub("[ '%s]", ""):gsub("ü", "v")
end

function M.func(translation, env)
  local input = compact(env.engine.context.input)
  local exact, english, rest = {}, {}, {}
  local buffered = 0
  local function emit(group)
    for _, candidate in ipairs(group) do yield(candidate) end
  end
  for candidate in translation:iter() do
    if buffered < 64 then
      local original = candidate:get_genuine()
      local spelling = compact(original.comment)
      local whole = candidate.start == 0 and candidate._end == #env.engine.context.input
      local is_english = whole and candidate.text:match("^[A-Za-z]+$")
        and candidate.text:lower() == input
      if is_english then
        english[#english + 1] = candidate
      elseif whole and spelling ~= "" and spelling == input then
        exact[#exact + 1] = candidate
      else
        rest[#rest + 1] = candidate
      end
      candidate.comment = ""
      buffered = buffered + 1
    else
      if buffered == 64 then
        emit(exact); emit(english); emit(rest)
        buffered = 65
      end
      candidate.comment = ""
      yield(candidate)
    end
  end
  if buffered <= 64 then emit(exact); emit(english); emit(rest) end
end
return M
