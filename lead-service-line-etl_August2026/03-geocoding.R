# setup ------------------------------------------------------------------

pacman::p_load("readr", "dplyr", "tidygeocoder", "sf", "mapview")

dir <- here::here("lead-service-line-etl_August2026")

# import data ------------------------------------------------------------

data <- read_csv(here::here(dir, "data", "lead_service_line_addresses.csv"))
# geocode addresses ------------------------------------------------------

tictoc::tic("geocoding")

geocodes <-
  data |> 
  mutate(address_full = paste(address, town, "NJ", zip, sep = ", "),
  .after = town  
) |> 
  geocode(
    address = address_full,
    method = "google",
    lat = "latitude",
    long = "longitude"
  )

tictoc::toc() # ~30 mins for 10549 addresses

length(unique(geocodes$address)) # 10549

# create shapefile -------------------------------------------------------

shapefile <-
  geocodes |> 
  unique() |> 
  st_as_sf(
    coords = c("longitude", "latitude"),
    crs = "EPSG:4326",
    remove = FALSE,
    na.fail = FALSE
  )

# export -----------------------------------------------------------------

write_csv(geocodes, file = here::here(dir, "data_intermediate", "lead_service_line_addresses_geocoded.csv"))
write_sf(shapefile, here::here(dir, "data_intermediate", "lead_service_line_addresses_geocoded.gpkg"))