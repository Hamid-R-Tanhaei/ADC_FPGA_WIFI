
# PlanAhead Launch Script for Post-Synthesis floorplanning, created by Project Navigator

create_project -name SPARTAN6_PROJ_ISE -dir "D:/NewDev/RF_RxTx/SPARTAN6_PROJ_ISE/planAhead_run_2" -part xc6slx9tqg144-2
set_property design_mode GateLvl [get_property srcset [current_run -impl]]
set_property edif_top_file "D:/NewDev/RF_RxTx/SPARTAN6_PROJ_ISE/Top_Design.ngc" [ get_property srcset [ current_run ] ]
add_files -norecurse { {D:/NewDev/RF_RxTx/SPARTAN6_PROJ_ISE} {ipcore_dir} }
add_files [list {ipcore_dir/cordic_abs.ncf}] -fileset [get_property constrset [current_run]]
add_files [list {ipcore_dir/DDS1.ncf}] -fileset [get_property constrset [current_run]]
add_files [list {ipcore_dir/fft32.ncf}] -fileset [get_property constrset [current_run]]
add_files [list {ipcore_dir/Fir_filter.ncf}] -fileset [get_property constrset [current_run]]
set_property target_constrs_file "CONSTRAINTS_RF_RxTx_v1.ucf" [current_fileset -constrset]
add_files [list {CONSTRAINTS_RF_RxTx_v1.ucf}] -fileset [get_property constrset [current_run]]
link_design
