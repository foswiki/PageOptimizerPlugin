# ---+ Extensions
# ---++ PageOptimizerPlugin
# This is the configuration used by the <b>PageOptimizerPlugin</b>.

# **BOOLEAN**
# If enabled, the final markup as generated by foswiki is cleaned up.
# Disable this flag for debugging foswiki's own html output.
$Foswiki::cfg{PageOptimizerPlugin}{CleanUpHTML} = 1;

# **BOOLEAN**
# If enabled, all JavaScript files will be combined and cached into one file.
$Foswiki::cfg{PageOptimizerPlugin}{OptimizeJavaScript} = 1;

# **BOOLEAN**
# If enabled, all stylesheets will be combined and cached into one file.
$Foswiki::cfg{PageOptimizerPlugin}{OptimizeStylesheets} = 1;

# **BOOLEAN**
# If enabled, the plugin will gather statistics about which css and js files
# have been combined into a single cache file. This information can be
# retrieved using the <code>statistics</code> rest handler of the
# PageOptimizerPlugin to be reviewed for further optimization of which assets
# shall be combined and which ones should stay separate for better cache
# reusage.
$Foswiki::cfg{PageOptimizerPlugin}{GatherStatistics} = 0;

1;
