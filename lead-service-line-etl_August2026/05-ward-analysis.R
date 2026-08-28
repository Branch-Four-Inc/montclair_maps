# setup ------------------------------------------------------------------

pacman::p_load("readr", "dplyr", "sf", "mapview", "gtsummary")

dir <- here::here("lead-service-line-etl_August2026")

# import data ------------------------------------------------------------

wards_sf <- read_sf(here::here(dir, "data_raw", "ward_boundaries_nj.gpkg"))
service_lines_sf <- read_sf(here::here(
  dir,
  "data",
  "lead_service_line_addresses_geocoded_annotated.gpkg"
))

# transform ward geometries ----------------------------------------------

wards_sf <- wards_sf |> st_transform(crs = "EPSG: 4326")

mapview(wards_sf)

# join service lines with wards ------------------------------------------

service_lines_wards <-
  service_lines_sf |>
  st_join(wards_sf)

mapview(service_lines_wards) + mapview(wards_sf, col.regions = "yellow")

# keep wards that join with service lines --------------------------------

montclair_sf <-
  wards_sf |>
  filter(WARD_KEY %in% service_lines_wards$WARD_KEY)

# check service lines outside of Montclair Township
mapview(montclair_sf, col.regions = "yellow") +
  mapview(service_lines_wards |> filter(MUN_NAME != "Montclair Township"))

# add PSL materials info -------------------------------------------------

service_lines_wards <-
  service_lines_wards |>
  mutate(service_line = case_when(
    service_line == "O" & stringr::str_detect(stringr::str_to_upper(csl_other), "BRASS") ~ "B",
    service_line == "O" & stringr::str_detect(stringr::str_to_upper(csl_other), "IRON")  ~ "Iron",
    service_line == "O" & stringr::str_detect(stringr::str_to_upper(csl_other), "PVC")   ~ "PVC",
    service_line == "O" & stringr::str_detect(stringr::str_to_upper(csl_other), "POLY")  ~ "Poly",
    .default = service_line
  ))

service_lines_wards <-
  service_lines_wards |>
  # replace abbreviations with words
  mutate(across(
    .cols = c(psl_materials, service_line),
    .fns = ~ case_when(
      . == "C" ~ "Copper",
      . == "G" ~ "Galvanized",
      . == "B" ~ "Brass",
      . == "L" ~ "Lead",
      #. == "O" ~ "O", # we don't know what "O" means
      . == "Iron" ~ "Iron",
      . == "PVC" ~ "PVC",
      . == "Poly" ~ "Poly",
      . == "UX" ~ "Unknown",
      .default = NA
    )
  ))

# add program qualification variable -------------------------------------

# src: https://www.montclairnjusa.org/Government/Departments/Water-Bureau-and-Sewer-Utility/2026-Lead-Service-Replacement-Program
service_lines_wards <-
  service_lines_wards |>
  mutate(
    replacement_program_eligibility = case_when(
      service_line %in% c("Lead", "Galvanized", "Brass") ~ "Qualified",
      service_line %in% c("Unknown") ~ "Verification needed",
      service_line %in% c("Copper") ~ "No further action required",
      .default = NA
    )
  )


# count service lines by ward --------------------------------------------

tbl_municipalities <-
  service_lines_wards |>
  st_drop_geometry() |>
  tbl_summary(
    include = c(MUN_NAME),
    sort = list(MUN_NAME ~ "frequency")
  ) |>
  modify_caption("Number of service lines by municipality")
tbl_municipalities

tbl_montclair <-
  service_lines_wards |>
  filter(MUN_NAME == "Montclair Township") |>
  st_drop_geometry() |>
  tbl_summary(
    include = c(suspected_lead, WARD_CODE),
    by = WARD_CODE,
    percent = "column"
  ) |>
  add_overall() |>
  modify_caption(
    "Number of service lines in<br>Montclair suspected of lead by ward"
  )
tbl_montclair

tbl_service_line <-
  service_lines_wards |>
  filter(MUN_NAME == "Montclair Township") |>
  st_drop_geometry() |>
  tbl_summary(
    include = c(service_line, replacement_program_eligibility, WARD_CODE),
    by = WARD_CODE,
    percent = "column"
  ) |>
  add_overall() |>
  modify_caption(
    "Service line materials in Montclair by ward"
  )
tbl_service_line

tbl_service_line_suspected <-
  service_lines_wards |>
  filter(MUN_NAME == "Montclair Township") |>
  filter(suspected_lead == "Y") |>
  st_drop_geometry() |>
  tbl_summary(
    include = c(service_line, replacement_program_eligibility, WARD_CODE),
    by = WARD_CODE,
    percent = "column"
  ) |>
  add_overall() |>
  modify_caption(
    "Service line materials in<br>Montclair **suspected of lead** by ward"
  )
tbl_service_line_suspected

# check suspected lead by service line material --------------------------

service_lines_wards |>
  st_drop_geometry() |>
  count(suspected_lead, service_line) |>
  gt::gt()

# export outputs ---------------------------------------------------------

write_sf(
  obj = montclair_sf,
  dsn = here::here(dir, "data", "ward_boundaries_montclair_nj.gpkg")
)

tbl_municipalities |>
  as_gt() |>
  gt::gtsave(
    filename = here::here(
      dir,
      "output",
      "tbl_service_lines_by_municipality.png"
    )
  )

tbl_montclair |>
  as_gt() |>
  gt::gtsave(
    filename = here::here(
      dir,
      "output",
      "tbl_service_lines_by_montclair_ward.png"
    )
  )

tbl_service_line |>
  as_gt() |>
  gt::gtsave(
    filename = here::here(
      dir,
      "output",
      "tbl_service_line_materials_by_montclair_ward.png"
    )
  )

tbl_service_line_suspected |>
  as_gt() |>
  gt::gtsave(
    filename = here::here(
      dir,
      "output",
      "tbl_service_line_materials_suspected_by_montclair_ward.png"
    )
  )
