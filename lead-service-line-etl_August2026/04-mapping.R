# setup ------------------------------------------------------------------

pacman::p_load("readr", "dplyr", "sf", "mapview", "gtsummary")

dir <- here::here("lead-service-line-etl_August2026")

# import data ------------------------------------------------------------

data <- read_csv(here::here(
  dir,
  "data",
  "lead_service_line_addresses_geocoded_annotated.csv"
))
data_sf <- data |>
  st_as_sf(
    coords = c("longitude_adj", "latitude_adj"),
    crs = "EPSG:4326",
    remove = FALSE,
    na.fail = FALSE
  )

# remove the incomplete addresses (ones without a street number)
data_sf <- data_sf |> filter(flag_incomplete == 0)

# create map -------------------------------------------------------------

lead_yes <- data_sf |> filter(suspected_lead == "Y")
lead_no <- data_sf |> filter(suspected_lead == "N")

map <-
  mapview(
    lead_no,
    layer.name = "Suspected lead - No",
    col.regions = "#4B0055",
    color = "#FFFFFF",
    lwd = 1
  ) +
  mapview(
    lead_yes,
    layer.name = "Suspected lead - Yes",
    col.regions = "#FDE333"
  )

# summary table ----------------------------------------------------------

table <-
  data_sf |>
  sf::st_drop_geometry() |>
  mutate(line_id = row_number()) |>
  tbl_summary(include = c(suspected_lead)) |>
  modify_caption("Proportion of service lines suspected of lead") |>
  as_gt()

# export -----------------------------------------------------------------

write_sf(
  obj = data_sf,
  dsn = here::here(
    dir,
    "data",
    "lead_service_line_addresses_geocoded_annotated.gpkg"
  )
)

gt::gtsave(
  table,
  filename = here::here(dir, "output", "tbl_lead_service_lines.png")
)

mapshot2(map, url = here::here(dir, "output", "map_lead_service_lines.html"))

mapshot2(
  map,
  url = here::here(dir, "output", "map_lead_service_lines.html"),
  file = here::here(dir, "output", "map_lead_service_lines.png")
)
