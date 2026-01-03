// IMPORTS ---------------------------------------------------------------------

import clique/handle.{type Handle}
import clique/internal/mutable_dict.{type MutableDict as Dict} as dict
import clique/internal/path
import gleam/bool
import gleam/option.{None, Some}
import gleam/set

//

///
///
pub type EdgeLookup {
  EdgeLookup(
    edges: Dict(String, EdgeData),
    keys: Dict(String, Dict(String, set.Set(String))),
  )
}

///
///
pub type EdgeData {
  EdgeData(
    source: Handle,
    from: #(Float, Float),
    target: Handle,
    to: #(Float, Float),
    kind: String,
    path: String,
    cx: Float,
    cy: Float,
  )
}

//

///
///
pub fn new() -> EdgeLookup {
  EdgeLookup(edges: dict.new(), keys: dict.new())
}

//

pub fn has(lookup: EdgeLookup, source: Handle, target: Handle) -> Bool {
  let key =
    source.node
    <> ":"
    <> source.name
    <> "->"
    <> target.node
    <> ":"
    <> target.name

  dict.has_key(lookup.edges, key)
}

//

///
///
pub fn get(
  lookup: EdgeLookup,
  source: Handle,
  target: Handle,
) -> Result(EdgeData, Nil) {
  let key =
    source.node
    <> ":"
    <> source.name
    <> "->"
    <> target.node
    <> ":"
    <> target.name

  case dict.has_key(lookup.edges, key) {
    True -> Ok(dict.unsafe_get(lookup.edges, key))
    False -> Error(Nil)
  }
}

///
///
pub fn get_all(lookup: EdgeLookup, handle: Handle) -> List(EdgeData) {
  use <- bool.guard(!dict.has_key(lookup.keys, handle.node), [])
  let inner = dict.unsafe_get(lookup.keys, handle.node)
  use <- bool.guard(!dict.has_key(inner, handle.name), [])
  let keys = dict.unsafe_get(inner, handle.name)
  use data, key <- set.fold(keys, [])

  case dict.has_key(lookup.edges, key) {
    True -> [dict.unsafe_get(lookup.edges, key), ..data]
    False -> data
  }
}

//

///
///
pub fn insert(
  lookup: EdgeLookup,
  source: Handle,
  from: #(Float, Float),
  target: Handle,
  to: #(Float, Float),
  kind: String,
) -> EdgeLookup {
  let #(path, cx, cy) = path.default(kind, from, to)
  let data = EdgeData(source:, from:, target:, to:, kind:, path:, cx:, cy:)

  let key =
    source.node
    <> ":"
    <> source.name
    <> "->"
    <> target.node
    <> ":"
    <> target.name

  let edges = dict.insert(lookup.edges, key, data)
  let keys =
    lookup.keys
    |> dict.upsert(source.node, fn(inner) {
      case inner {
        Some(inner) ->
          dict.upsert(inner, source.name, fn(keys) {
            option.map(keys, set.insert(_, key))
            |> option.lazy_unwrap(fn() { set.from_list([key]) })
          })
        None -> dict.from_list([#(source.name, set.from_list([key]))])
      }
    })
    |> dict.upsert(target.node, fn(inner) {
      case inner {
        Some(inner) ->
          dict.upsert(inner, target.name, fn(keys) {
            option.map(keys, set.insert(_, key))
            |> option.lazy_unwrap(fn() { set.from_list([key]) })
          })
        None -> dict.from_list([#(target.name, set.from_list([key]))])
      }
    })

  EdgeLookup(edges:, keys:)
}

pub fn insert_edge(
  lookup: EdgeLookup,
  source: Handle,
  target: Handle,
  edge: EdgeData,
) -> EdgeLookup {
  let key =
    source.node
    <> ":"
    <> source.name
    <> "->"
    <> target.node
    <> ":"
    <> target.name

  let edges = dict.insert(lookup.edges, key, edge)
  let keys =
    lookup.keys
    |> dict.upsert(source.node, fn(inner) {
      case inner {
        Some(inner) ->
          dict.upsert(inner, source.name, fn(keys) {
            option.map(keys, set.insert(_, key))
            |> option.lazy_unwrap(fn() { set.from_list([key]) })
          })
        None -> dict.from_list([#(source.name, set.from_list([key]))])
      }
    })
    |> dict.upsert(target.node, fn(inner) {
      case inner {
        Some(inner) ->
          dict.upsert(inner, target.name, fn(keys) {
            option.map(keys, set.insert(_, key))
            |> option.lazy_unwrap(fn() { set.from_list([key]) })
          })
        None -> dict.from_list([#(target.name, set.from_list([key]))])
      }
    })

  EdgeLookup(edges:, keys:)
}

pub fn delete(lookup: EdgeLookup, source: Handle, target: Handle) -> EdgeLookup {
  let key =
    source.node
    <> ":"
    <> source.name
    <> "->"
    <> target.node
    <> ":"
    <> target.name

  let edges = dict.delete(lookup.edges, key)

  let keys = case dict.has_key(lookup.keys, source.node) {
    True -> {
      let inner = dict.unsafe_get(lookup.keys, source.node)
      case dict.has_key(inner, source.name) {
        True -> {
          let source_keys = dict.unsafe_get(inner, source.name)
          case set.size(source_keys) == 1 {
            True ->
              dict.insert(
                lookup.keys,
                source.node,
                dict.delete(inner, source.name),
              )

            False ->
              dict.insert(
                lookup.keys,
                source.node,
                dict.insert(inner, source.name, set.delete(source_keys, key)),
              )
          }
        }

        False -> lookup.keys
      }
    }

    False -> lookup.keys
  }

  let keys = case dict.has_key(keys, target.node) {
    True -> {
      let inner = dict.unsafe_get(keys, target.node)
      case dict.has_key(inner, target.name) {
        True -> {
          let target_keys = dict.unsafe_get(inner, target.name)
          case set.size(target_keys) == 1 {
            True ->
              dict.insert(keys, source.node, dict.delete(inner, target.name))

            False ->
              dict.insert(
                keys,
                source.node,
                dict.insert(inner, target.name, set.delete(target_keys, key)),
              )
          }
        }

        False -> keys
      }
    }

    False -> keys
  }

  EdgeLookup(edges:, keys:)
}

pub fn delete_node(lookup: EdgeLookup, node: String) -> EdgeLookup {
  let edges = {
    use <- bool.guard(!dict.has_key(lookup.keys, node), lookup.edges)
    let inner = dict.unsafe_get(lookup.keys, node)
    use edges, _, keys <- dict.fold(inner, lookup.edges)
    use edges, key <- set.fold(keys, edges)

    dict.delete(edges, key)
  }

  let keys = dict.delete(lookup.keys, node)

  EdgeLookup(edges:, keys:)
}

///
///
pub fn update_node(
  lookup: EdgeLookup,
  node: String,
  offset: #(Float, Float),
) -> EdgeLookup {
  let #(edges, _) = {
    use <- bool.guard(!dict.has_key(lookup.keys, node), #(
      lookup.edges,
      set.new(),
    ))
    let inner = dict.unsafe_get(lookup.keys, node)
    use #(edges, seen), _, keys <- dict.fold(inner, #(lookup.edges, set.new()))
    use #(edges, seen), key <- set.fold(keys, #(edges, seen))
    use <- bool.guard(set.contains(seen, key), #(edges, seen))

    case dict.has_key(edges, key) {
      True -> {
        let edge = dict.unsafe_get(edges, key)
        let from = case edge.source.node == node {
          True -> #(edge.from.0 +. offset.0, edge.from.1 +. offset.1)
          False -> edge.from
        }

        let to = case edge.target.node == node {
          True -> #(edge.to.0 +. offset.0, edge.to.1 +. offset.1)
          False -> edge.to
        }

        let #(path, cx, cy) = path.default(edge.kind, from, to)
        let updated_edge = EdgeData(..edge, from:, to:, path:, cx:, cy:)

        #(dict.insert(edges, key, updated_edge), set.insert(seen, key))
      }

      False -> #(edges, set.insert(seen, key))
    }
  }

  EdgeLookup(..lookup, edges:)
}

///
///
pub fn update(
  lookup: EdgeLookup,
  handle: Handle,
  position: #(Float, Float),
) -> EdgeLookup {
  let edges = {
    use <- bool.guard(!dict.has_key(lookup.keys, handle.node), lookup.edges)
    let inner = dict.unsafe_get(lookup.keys, handle.node)
    use <- bool.guard(!dict.has_key(inner, handle.name), lookup.edges)
    let keys = dict.unsafe_get(inner, handle.name)
    use edges, key <- set.fold(keys, lookup.edges)
    use <- bool.guard(!dict.has_key(edges, key), edges)

    let edge = dict.unsafe_get(edges, key)
    let from = case edge.source == handle {
      True -> position
      False -> edge.from
    }

    let to = case edge.target == handle {
      True -> position
      False -> edge.to
    }

    let #(path, cx, cy) = path.default(edge.kind, from, to)
    let updated_edge = EdgeData(..edge, from:, to:, path:, cx:, cy:)

    dict.insert(edges, key, updated_edge)
  }

  EdgeLookup(..lookup, edges:)
}

///
///
pub fn fold(lookup: EdgeLookup, init: a, f: fn(a, String, EdgeData) -> a) -> a {
  dict.fold(lookup.edges, init, f)
}
