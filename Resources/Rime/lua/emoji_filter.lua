local function init(env)
  env.emoji = {}
  local path = rime_api.get_shared_data_dir() .. "/opencc/emoji.txt"
  for line in io.lines(path) do
    local word, original, emoji = line:match("^(%S+)\t(%S+) +(%S+)")
    if word and word == original then
      env.emoji[word] = emoji
    end
  end
end

local function filter(input, env)
  local input_length = #env.engine.context.input
  local added = false
  for candidate in input:iter() do
    yield(candidate)
    if not added and candidate.start == 0 and candidate._end == input_length then
      local emoji = env.emoji[candidate.text]
      if emoji then
        added = true
        yield(ShadowCandidate(candidate, "emoji", emoji, "", false))
      end
    end
  end
end

return { init = init, func = filter }
