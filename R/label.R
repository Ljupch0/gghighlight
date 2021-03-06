# Labels

generate_labelled_layer <- function(layers, group_infos, label_key, label_params, max_labels) {
  layer_for_label <- choose_layer_for_label(layers, group_infos, label_key)
  if (is.null(layer_for_label)) {
    return(NULL)
  }

  layer <- layer_for_label$layer
  label_key <- layer_for_label$label_key

  switch(class(layer$geom)[1],
    GeomLine = generate_label_for_line(layer, label_key, label_params, max_labels = max_labels),
    GeomPoint = generate_label_for_point(layer, label_key, label_params, max_labels = max_labels),
    # TODO: To distinguish NULL, return list() to hide guides here.
    #       But, can we use more explicit representation?
    GeomBar = list(),
    abort("Unsupported geom!")
  )
}

choose_layer_for_label <- function(layers, group_infos, label_key) {
  show_label_key <- FALSE
  if (quo_is_call(label_key)) {
    # if label_key is a call we can't check if the necessary variables exist in
    # the data. Just pray that the proper layer will be choosed... :pray:
    label_keys <- purrr::rerun(length(layers), label_key)
  } else if (quo_is_symbol(label_key)) {
    # If label_key is a symbol, some layer must have the key in their data.
    label_key_text <- quo_text(label_key)
    layers <- purrr::keep(layers, ~ label_key_text %in% names(.$data))
    label_keys <- purrr::rerun(length(layers), label_key)
  } else if (quo_is_null(label_key)) {
    # If label_key is not specified, some key might be usable for label.
    group_keys <- purrr::map(group_infos, "key")
    idx <- !purrr::map_lgl(group_keys, is.null)
    layers <- layers[idx]
    # group keys may be multiple, but use the first one for convenience.
    label_keys <- purrr::map(group_keys[idx], 1L)
    # display which key was chosen for label
    show_label_key <- TRUE
  } else {
    abort("Invalid label_key!")
  }

  # If no layer has labellable variable, give up labelling
  if (length(layers) == 0) {
    return(NULL)
  }

  # If there's line, point or bar geom, choose it. (bar geom doesn't generate labels, though).
  for (fun in list(is_identity_line, is_identity_point, is_bar)) {
    idx <- purrr::map_lgl(layers, fun)
    if (any(idx)) {
      label_key <- label_keys[idx][[1]]
      if (show_label_key) message("label_key: ", quo_text(label_key))
      return(list(layer = layers[idx][[1]], label_key = label_key))
    }
  }

  # Other geoms are currently unsupported.
  return(NULL)
}

is_identity_line <- function(x) {
  is_direct_class(x$stat, "StatIdentity") && is_direct_class(x$geom, "GeomLine")
}

is_identity_point <- function(x) {
  is_direct_class(x$stat, "StatIdentity") && is_direct_class(x$geom, "GeomPoint")
}

is_bar <- function(x) is_direct_class(x$geom, "GeomBar")

is_direct_class <- function(x, class) identical(class(x)[1], class)

generate_label_for_line <- function(layer, label_key, label_params, max_labels) {
  mapping <- layer$mapping
  mapping$label <- label_key

  x_key <- layer$mapping$x
  group_key <- layer$mapping$group %||% layer$mapping$colour

  # To restore the original group, extract group keys (I don't know this is really necessary, though...)
  group_key_orig <- dplyr::groups(layer$data)

  data <- dplyr::group_by(layer$data, !!group_key)
  if (dplyr::n_groups(data) > max_labels) {
    inform("Too many data series, skip labeling")
    return(list())
  }
  
  rightmost_points <- dplyr::filter(data, !!x_key == max(!!x_key))
  # max value can appear multiple times, so ensure only one row per group
  rightmost_points <- dplyr::slice(rightmost_points, 1)

  # restore the original group
  rightmost_points <- dplyr::group_by(rightmost_points, !!!group_key_orig)

  call_ggrepel_with_params(mapping, rightmost_points, label_params)
}

generate_label_for_point <- function(layer, label_key, label_params, max_labels) {
  if (nrow(layer$data) > max_labels) {
    inform("Too many data points, skip labeling")
    return(list())
  }
  
  mapping <- layer$mapping
  mapping$label <- label_key

  if (inherits(layer$position, "PositionJitter") && is.null(layer$position$seed)) {
    # FIXME when this is fixed on upstream: https://github.com/tidyverse/ggplot2/issues/2507
    position <- clone_position(layer$position)
    position$seed <- sample.int(.Machine$integer.max, 1L)
    layer$position <- position
  }

  label_params$position <- layer$position

  call_ggrepel_with_params(mapping, layer$data, label_params)
}


call_ggrepel_with_params <- function(mapping, data, params) {
  ggrepel_quo <- quo(ggrepel::geom_label_repel(mapping, data, !!!params))
  eval_tidy(ggrepel_quo)
}
