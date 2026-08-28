
rm(list=ls())

library(tidycensus)
library(tidyverse)
library(dplyr)
library(data.table)
library(stringr)

Sys.getenv("CENSUS_API_KEY")

increment_id <- function(id, n = 1, num = "000") {
  
  prefix <- sub("_(\\d+)$", "", id)
  
  if (is.null(num)) {
    num  <- sub("^.*_(\\d+)$", "\\1", id)} 
  
  new_num <- as.numeric(num) + n
  
  new_id <- sprintf("%s_%0*d", prefix, nchar(num), new_num)
  
  return(new_id)}

acs_year = 2024 
acs_data = "acs5" 


var_codes <- load_variables(year = acs_year,
                            dataset = acs_data, 
                            cache = TRUE)

vars <- c("B25003_001", "B25003_002", "B25003_003", "B19001_001", "B19001_002", "B19001_003", 
          "B19001_004", "B19001_005", "B19001_006", "B19001_007", "B19001_008", "B19001_009", 
          "B19001_010", "B19001_011", "B19001_012", "B19001_013", "B19001_014", "B19001_015", 
          "B19001_016","B19001_017", "B02001_001", "B02001_002", "B02001_003", "B02001_004", 
          "B02001_005", "B02001_006", "B02001_007", "B02001_008", "B02001_009", "B02001_010", 
          "B15003_001", "B15003_002", "B15003_003", "B15003_004", "B15003_005", "B15003_006", 
          "B15003_007", "B15003_008", "B15003_009", "B15003_010", "B15003_011", "B15003_012", 
          "B15003_013", "B15003_014", "B15003_015", "B15003_016", "B15003_017", "B15003_018", 
          "B15003_019", "B15003_020", "B15003_021", "B15003_022", "B15003_023", "B15003_024", "B15003_025")

df_county <- get_acs(geography = "tract", # set geography level: us, state, county, county subdivision, place, tract, block, block group, zcta
                     #table = "K201901",
                     variables = vars,
                     state = "NJ", # set state 
                     county = "013", # set county FIPS code
                     survey = acs_data,
                     year = acs_year) 


# merge in variable names 
df_county2 <- df_county %>% 
  left_join(var_codes, by = c('variable' = 'name') ) 

View(df_county2)

write.csv(df_county2, "MontclairTractTest.csv", row.names = FALSE)