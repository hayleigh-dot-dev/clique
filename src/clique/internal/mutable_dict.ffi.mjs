import { List, Empty, Ok, Error } from "../../gleam.mjs";

export const make = () => new Map()

//

export const get = (dict, key) => dict.get(key)

export const has_key = (dict, key) => dict.has(key)

export const keys = (dict) => List.fromArray(Array.from(dict.keys()))

export const values = (dict) => List.fromArray(Array.from(dict.values()))

export const to_list = (dict) => List.fromArray(Array.from(dict.entries()))

export const to_json = (dict, key_to_json, value_to_json) => {
  const json = {}

  for (const [key, value] of dict.entries()) {
    json[key_to_json(key)] = value_to_json(value)
  }

  return json
}

//

export const insert = (dict, key, value) => {
  dict.set(key, value)

  return dict
}

export const remove = (dict, key) => {
  dict.delete(key)

  return dict
}
