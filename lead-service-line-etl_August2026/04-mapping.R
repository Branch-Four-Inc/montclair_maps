# setup ------------------------------------------------------------------

pacman::p_load("readr", "dplyr", "sf", "mapview", "gtsummary", "leaflet")

dir <- here::here("lead-service-line-etl_August2026")

readRenviron("C:\\Users\\stm4z\\OneDrive - branchfour.org\\Scripts\\.env")

carto_key <- Sys.getenv("CARTO_API_KEY")
if (carto_key == "") stop("CARTO_API_KEY not found - set it in .Renviron")

Sys.setenv(CHROMOTE_CHROME = "C:/Program Files/Google/Chrome/Application/chrome.exe")


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

lead_yes <- data_sf |> filter(suspected_lead == "Y")
lead_no <- data_sf |> filter(suspected_lead == "N")


# build base map with carto API key ----------------------------------------

carto_attr <- '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, &copy; <a href="https://carto.com/attributions">CARTO</a>'


base_map <- leaflet() |>
  addTiles(
    urlTemplate = paste0(
      "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png?key=",
      carto_key
    ),
    attribution = carto_attr,
    group = "CartoDB.Positron",
    options = tileOptions(subdomains = "abcd")
  ) |>
  addTiles(
    urlTemplate = paste0(
      "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png?key=",
      carto_key
    ),
    attribution = carto_attr,
    group = "CartoDB.DarkMatter",
    options = tileOptions(subdomains = "abcd")
  ) |>
  addLayersControl(baseGroups = c("CartoDB.Positron", "CartoDB.DarkMatter")) |>
  setView(lng = 0, lat = 0, zoom = 13.5)  # Adjust the zoom level here (e.g., 12)

# create map -------------------------------------------------------------


map <-
  mapview(
    lead_no,
    map = base_map,
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
