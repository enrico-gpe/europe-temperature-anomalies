library(terra)
options(download.file.method = "libcurl")

# =======================================================
# 1. MACRO EUROPEAN AREA CONFIGURATION
# =======================================================
LAT_TOP    <- 75
LAT_BOTTOM <- 30
LON_LEFT   <- -30   
LON_RIGHT  <- 50

cat("=======================================================\n")
cat("  EUROPEAN TEMPERATURE ANOMALY ANALYSIS SYSTEM V.3     \n")
cat("=======================================================\n")

# =======================================================
# 2. INTERACTIVE GFS RUN SELECTION (8 TIME SLOTS)
# =======================================================
cat("Select the GFS run model to download:\n")
cat("[1] 00Z (02:00 AM Italian Time) - Main Night Run\n")
cat("[2] 03Z (05:00 AM Italian Time)\n")
cat("[3] 06Z (08:00 AM Italian Time) - Morning Run\n")
cat("[4] 09Z (11:00 AM Italian Time)\n")
cat("[5] 12Z (02:00 PM Italian Time) - Main Afternoon Run\n")
cat("[6] 15Z (05:00 PM Italian Time)\n")
cat("[7] 18Z (08:00 PM Italian Time) - Evening Run\n")
cat("[8] 21Z (11:00 PM Italian Time)\n")
cat("Choice (1-8): ")

scelta_ora <- as.integer(readLines(con = stdin(), n = 1))
if (is.na(scelta_ora) || scelta_ora < 1 || scelta_ora > 8) scelta_ora <- 1

fasce_orarie <- c("00", "03", "06", "09", "12", "15", "18", "21")
run_scelto   <- fasce_orarie[scelta_ora]

# =======================================================
# 3. FORECAST LEAD TIME INPUT (DAYS AHEAD)
# =======================================================
cat("\nHow many days ahead do you want to forecast? (0=Today, 1=Tomorrow, etc.): ")
giorni_vanto <- as.integer(readLines(con = stdin(), n = 1))
if (is.na(giorni_vanto)) giorni_vanto <- 1 

ore_vanto <- giorni_vanto * 24
forecast_str <- paste0("f", sprintf("%03d", ore_vanto))

data_oggi <- Sys.Date()
data_previsione <- data_oggi + giorni_vanto
giorno_clima_target <- as.integer(format(data_previsione, "%j"))

dir.create("data", showWarnings = FALSE)
file_grib  <- "data/gfs_global_current.grb" # Temporary file forced for fresh caching
file_clima <- "data/air.sig995.day.ltm.1981-2010.nc"

# Remove old session files to ensure a fresh download is pulled
if (file.exists(file_grib)) file.remove(file_grib)

# =======================================================
# 4. ROBUST DOWNLOADS WITH SMART FALLBACK (XYGRIB STYLE)
# =======================================================
if (!file.exists(file_clima)) {
  cat("Downloading Global Long-Term Climatology dataset...\n")
  url_clima <- "https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis.derived/surface/air.sig995.day.ltm.1981-2010.nc"
  download.file(url_clima, file_clima, mode = "wb", quiet = TRUE)
}

date_str  <- format(data_oggi, "%Y%m%d")
data_ieri <- data_oggi - 1

# Generate an optimized fallback queue (Date, Run, Hour Offset)
tabella_tentativi <- list(
  list(data = data_oggi, run = run_scelto, offset = 0),
  list(data = data_ieri, run = run_scelto, offset = 24), 
  list(data = data_oggi, run = "12", offset = 0),
  list(data = data_oggi, run = "00", offset = 0),
  list(data = data_ieri, run = "18", offset = 24),
  list(data = data_ieri, run = "12", offset = 24)
)

chiavi <- sapply(tabella_tentativi, function(x) paste(format(x$data, "%Y%m%d"), x$run))
tabella_tentativi <- tabella_tentativi[!duplicated(chiavi)]

successo <- FALSE
options(warn = -1) # Suppress network logs from console output

for (tentativo in tabella_tentativi) {
  current_data <- tentativo$data
  current_run  <- tentativo$run
  current_off  <- tentativo$offset
  
  ore_effettive  <- ore_vanto + current_off
  f_str_corretto <- paste0("f", sprintf("%03d", ore_effettive))
  
  url_gfs <- paste0(
    "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?",
    "file=gfs.t", current_run, "z.pgrb2.0p25.", f_str_corretto,
    "&lev_1000_mb=on&var_TMP=on&",
    "toplat=", LAT_TOP, "&bottomlat=", LAT_BOTTOM,
    "&dir=%2Fgfs.", format(current_data, "%Y%m%d"), "%2F", current_run, "%2Fatmos"
  )
  
  cat(paste0("Checking GFS Server -> Date: ", format(current_data, "%d/%m/%Y"), " | Run: ", current_run, "Z (", f_str_corretto, ")...\n"))
  
  esito <- tryCatch({
    download.file(url_gfs, file_grib, mode = "wb", quiet = TRUE)
    TRUE
  }, error = function(e) { FALSE })
  
  if (esito && file.exists(file_grib) && file.info(file_grib)$size > 5000) { 
    cat(paste0("[SUCCESS] Successfully hooked GFS Run: ", current_run, "Z on ", format(current_data, "%d/%m/%Y"), "\n"))
    run_scelto <- current_run
    data_oggi  <- current_data
    successo   <- TRUE
    break
  }
}
options(warn = 0) # Restore standard warnings

if (!successo) {
  stop("Critical Error: NOAA servers are currently unreachable. Please try again later.")
}

# =======================================================
# 5. GEOSPATIAL PROCESSING & GEOMETRIC ROTATION (0-360)
# =======================================================
gfs_raw <- rast(file_grib)
clima_cube <- rast(file_clima)
clima_giorno_raw <- clima_cube[[giorno_clima_target]]

# Fix global coordinate extents
ext(gfs_raw)          <- c(0, 360, ext(gfs_raw)$ymin, ext(gfs_raw)$ymax)
ext(clima_giorno_raw) <- c(0, 360, ext(clima_giorno_raw)$ymin, ext(clima_giorno_raw)$ymax)

# Rotate to standard -180 to +180 grid to natively bind the Iberian Peninsula
gfs_rotated   <- rotate(gfs_raw)
clima_rotated <- rotate(clima_giorno_raw)

# Preliminary crop to the European macro-bounding box
estensione_target <- ext(LON_LEFT, LON_RIGHT, LAT_BOTTOM, LAT_TOP)
gfs_europa        <- crop(gfs_rotated, estensione_target)
clima_europa      <- crop(clima_rotated, estensione_target)

crs(gfs_europa)   <- "EPSG:4326"
crs(clima_europa) <- "EPSG:4326"

# Resample climatology grid to match high-resolution GFS matrices
clima_regridded <- resample(clima_europa, gfs_europa, method = "bilinear")

# =======================================================
# 6. UNIT CONVERSION & EUROPEAN POLITICAL MASKING
# =======================================================
gfs_valori   <- minmax(gfs_europa)
clima_valori <- minmax(clima_regridded)

gfs_celsius   <- if(gfs_valori[2,1] > 100) gfs_europa - 273.15 else gfs_europa
clima_celsius <- if(clima_valori[2,1] > 100) clima_regridded - 273.15 else clima_regridded

# Extracting European political world map borders
confini_euro <- maps::map("world", interp = FALSE, plot = FALSE, fill = TRUE,
                          regions = c("Albania", "Austria", "Belgium", "Bulgaria", "Belarus",
                                      "Switzerland", "Czech Republic", "Germany", "Denmark",
                                      "Spain", "Estonia", "Finland", "France", "UK", "Greece",
                                      "Croatia", "Hungary", "Ireland", "Iceland", "Italy",
                                      "Lithuania", "Luxembourg", "Latvia", "Moldova", "Macedonia",
                                      "Netherlands", "Norway", "Poland", "Portugal", "Romania",
                                      "Russia", "Slovakia", "Slovenia", "Sweden", "Ukraine", 
                                      "Serbia", "Montenegro", "Bosnia and Herzegovina"))

# Convert map layout to sf and then into a Terra SpatVector object
sf_euro <- sf::st_as_sf(confini_euro)
vettore_euro <- vect(sf_euro)
crs(vettore_euro) <- "EPSG:4326"

# Apply mask: pixels outside European boundaries are forced to NA
gfs_solo_europa   <- mask(gfs_celsius, vettore_euro)
clima_solo_europa <- mask(clima_celsius, vettore_euro)
anomala_europa    <- gfs_solo_europa - clima_solo_europa

# =======================================================
# 7. GRAPHICAL PLOTTING (MASKED DATA ONLY)
# =======================================================
range_temp <- c(floor(min(minmax(gfs_solo_europa)[1,1], minmax(clima_solo_europa)[1,1], na.rm=TRUE)), 
                ceiling(max(minmax(gfs_solo_europa)[2,1], minmax(clima_solo_europa)[2,1], na.rm=TRUE)))

limite_scala <- ceiling(max(abs(minmax(anomala_europa)), na.rm = TRUE))
if (limite_scala < 4) limite_scala <- 4

dev.new(width = 15, height = 5, noRStudioGD = TRUE)
par(mfrow = c(1, 3), mar = c(4, 4, 4, 5), oma = c(0, 0, 3, 0))

# Map 1: Historical Climatology
plot(clima_solo_europa, col = hcl.colors(100, "RdYlBu", rev = TRUE),
     main = "1. Long-Term Climate (Europe Only)", range = range_temp, xlab = "Longitude", ylab = "Latitude")
maps::map("world", add = TRUE, col = "gray30", lwd = 0.5)
grid(lty = "dotted", col = "gray40")

# Map 2: GFS Forecast
plot(gfs_solo_europa, col = hcl.colors(100, "RdYlBu", rev = TRUE),
     main = paste0("2. GFS Forecast (Run ", run_scelto, "Z)\nValid: ", format(data_previsione, "%d/%m/%Y")), 
     range = range_temp, xlab = "Longitude", ylab = "Latitude")
maps::map("world", add = TRUE, col = "gray30", lwd = 0.5)
grid(lty = "dotted", col = "gray40")

# Map 3: Thermal Anomaly
plot(anomala_europa, col = hcl.colors(120, "RdBu", rev = TRUE), range = c(-limite_scala, limite_scala), 
     main = "3. Temperature Anomaly (GFS - Climate)", xlab = "Longitude", ylab = "Latitude")
contour(anomala_europa, add = TRUE, col = "black", lwd = 0.3, levels = seq(-limite_scala, limite_scala, by = 2))
maps::map("world", add = TRUE, col = "gray30", lwd = 0.5)
grid(lty = "dotted", col = "gray40")

mtext(paste0("Masked Thermal Analysis - Target: ", format(data_previsione, "%d/%m/%Y"), " [Run ", run_scelto, "Z]"), 
      outer = TRUE, cex = 1.3, font = 2)

# =======================================================
# 8. STATISTICAL EXTRACTION AND PROMPT REPORTING
# =======================================================
max_clima    <- global(clima_solo_europa, "max", na.rm = TRUE)[1,1]
max_forecast <- global(gfs_solo_europa, "max", na.rm = TRUE)[1,1]
min_forecast <- global(gfs_solo_europa, "min", na.rm = TRUE)[1,1]

max_anomalia_calda  <- global(anomala_europa, "max", na.rm = TRUE)[1,1]
max_anomalia_fredda <- global(anomala_europa, "min", na.rm = TRUE)[1,1]

cat("\n=======================================================\n")
cat("      TEMPERATURE EXTREMES REPORT (EUROPE LAND ONLY)    \n")
cat("=======================================================\n")
cat(paste0("Target Forecast Date : ", format(data_previsione, "%d/%m/%Y"), "\n"))
cat("-------------------------------------------------------\n")
cat(paste0("• MAXIMUM Temp expected (GFS)      : ", round(max_forecast, 1), " °C\n"))
cat(paste0("• MINIMUM Temp expected (GFS)      : ", round(min_forecast, 1), " °C\n"))
cat(paste0("• Historical MAX Temp (Climate)    : ", round(max_clima, 1), " °C\n"))
cat("-------------------------------------------------------\n")
cat(paste0("• Peak WARM ANOMALY (Above Normal) : +", round(max_anomalia_calda, 1), " °C\n"))
cat(paste0("• Peak COLD ANOMALY (Below Normal) : ", round(max_anomalia_fredda, 1), " °C\n"))
cat("=======================================================\n\n")