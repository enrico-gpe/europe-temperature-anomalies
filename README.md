# 2m-anomalies-europe

A robust, interactive R script to fetch, process, and map 2-meter thermal anomalies across the European continent using real-time GFS (Global Forecast System) model data and long-term historical climatology.

---

## 📊 Visual Outputs & Terminal Interface

The pipeline processes global meteorological grids, slices them down to the European domain, and prints real-time statistics. Below is a complete overview of the execution flow:

### 1. Terminal Interactive Prompt & Report
When executed, the script prompts the user to select the GFS cycle run and forecast lead time. It features a smart fallback system to ensure data availability and outputs a clean text-based extreme metrics report directly to the console:

![Terminal Interactive Prompt and Report](plots/map.jpg)

### 2. Masked Landmass Analysis (Final Output)
By applying a strict political boundary vector, the script filters out marine areas and neighboring continents to isolate and analyze the European territory exclusively:

![Masked European Analysis](plots/analysys.jpg)

---

## 🎛️ Key Features

* **Interactive Run Selection:** Choose between all 8 daily GFS cycle runs (00Z, 03Z, 06Z, 09Z, 12Z, 15Z, 18Z, 21Z) straight from the R console.
* **Smart Fallback Architecture (XyGrib Style):** If NOAA servers are currently uploading data or a specific run is incomplete, the script automatically shifts backwards to the closest available historical run and compensates the forecast hours to keep the map target accurate without crashing.
* **Seamless Coordinate Rotation:** Handles native 0-360° GFS coordinate wrapping, flawlessly binding the Iberian Peninsula and Atlantic boundaries to standard -180° to +180° projections.
* **Strict European Masking:** Leverages spatial political boundaries to filter out ocean data and neighboring continents (e.g., North Africa, Middle East), displaying data exclusively over the European landmass.
* **Automated Extreme Metrics:** Computes and prints a concise text-based terminal report showing forecasted European maximum/minimum temperatures, historical records, and exact peak positive/negative anomalies.

---

## 🛠️ Prerequisites & Installation

Ensure you have R installed along with the following required geospatial libraries:

```R
install.packages(c("terra", "sf", "maps"))


## 🚀 How to Run

    Clone this repository or download the main script.

    Open your terminal or R console and source the file:
	
    source("2m_anomalies_europe.R")

---