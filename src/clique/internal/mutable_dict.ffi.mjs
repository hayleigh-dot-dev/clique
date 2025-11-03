import { List, Empty, Ok, Error } from "../../gleam.mjs";

export const make = () => new Map()

//

export const get = (dict, key) => {
  const value = dict.get(key)

  if (value !== undefined) {
    return new Ok(value)
  } else {
    return new Error(undefined)
  }
}

export const has_key = (dict, key) => dict.has(key)

export const keys = (dict) => List.fromArray(Array.from(dict.keys()))

export const values = (dict) => List.fromArray(Array.from(dict.values()))

export const to_list = (dict) => List.fromArray(Array.from(dict.entries()))

//

export const insert = (dict, key, value) => {
  dict.set(key, value)

  return dict
}

export const remove = (dict, key) => {
  dict.delete(key)

  return dict
}
