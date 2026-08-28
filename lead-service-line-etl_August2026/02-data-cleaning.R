
# load packages ----------------------------------------------------------

pacman::p_load("readr", "dplyr", "stringr")

# import data ------------------------------------------------------------

data <- read_csv(here::here("lead-service-line-etl_August2026", "data_intermediate", "lead_service_line_addresses.csv"))

# clean addresses --------------------------------------------------------

clean_data <-
  data |> 
  unique() |> 
  # convert all addresses to uppercase
  mutate(
    address = str_to_upper(address),
    town = str_to_upper(town)
  ) |> 
  # extract zip codes from address field
  mutate(
    clean_address = str_squish(str_extract(address, ".+?(?=[0-9]{5})")),
    clean_zip = str_extract(address, "[0-9]{5}")) |> 
  mutate(
    address = if_else(is.na(zip), clean_address, address),
    zip = if_else(is.na(zip), clean_zip, zip),
  ) |> 
  # clean up zip code field
  mutate(
    excess_address = str_squish(str_extract(zip, ".+?(?=[0-9]{5})")),
    clean_zip = str_extract(zip, "[0-9]{5}"),
    clean_address = str_c(address, excess_address)
  ) |>
  mutate(
    address = if_else(!is.na(clean_address), clean_address, address),
    zip = clean_zip
  ) |>
  # remove intermediate variables
  select(-c(clean_address, clean_zip, excess_address))


clean_data <- clean_data |>
  mutate(
    zip = if_else(is.na(zip), "07042", zip),
    address = if_else(address == "218 UPPER MOUNTN AVENUE-CARRIAGE/D",
                      "218 UPPER MOUNTAIN AVENUE", address)
  )


# export clean data ------------------------------------------------------

write_csv(
  x = clean_data,
  file = here::here("lead-service-line-etl_August2026", "data", "lead_service_line_addresses.csv")
)
