/**
 *  littoSIM_GEN
 *  Authors: Brice, Cécilia, Elise, Etienne, Fredéric, Marion, Nicolas B, Nicolas M, Xavier 
 * 
 *  Description : LittoSim est un jeu sérieux qui se présente sous la forme d’une simulation intégrant à la fois 
 *  un modèle de submersion marine, la modélisation de différents rôles d’acteurs agissant sur le territoire 
 *  et la possibilité de mettre en place différents scénarios de prévention des submersions qui seront contrôlés
 *  par les utilisateurs de la simulation en fonction de leur rôle. 
 */

model Manager

import "params_models/params_manager.gaml"

global {

	// Lisflood configuration for the study area
	string application_name 	<- shapes_def["APPLICATION_NAME"]; // used to name exported files
	// sea heights file sent to Lisflood
	string lisflood_bdy_file 	->{floodEventType ="HIGH_FLOODING"?flooding_def["LISFLOOD_BDY_HIGH_FILENAME"]   // "oleron2016_Xynthia.bdy" 
								:(floodEventType ="LOW_FLOODING"?flooding_def["LISFLOOD_BDY_LOW_FILENAME"] // "oleron2016_Xynthia-50.bdy" : Xynthia - 50 cm 
		  						:langs_def at 'MSG_FLOODING_TYPE_PROBLEM' at configuration_file["LANGUAGE"])};
	// paths to Lisflood
	string lisfloodPath 				<- flooding_def["LISFLOOD_PATH"]; // absolute path to Lisflood : "C:/lisflood-fp-604/"
	string lisfloodRelativePath 		<- flooding_def["LISFLOOD_RELATIVE_PATH"]; // Lisflood folder relatife path 
	string results_lisflood_rep 		<- flooding_def["RESULTS_LISFLOOD_REP"]; // Lisflood results folder
	string lisflood_par_file 			-> {"inputs/"+"LittoSIM_GEN_"+application_name+"_config_"+floodEventType+timestamp+".par"}; // parameter file
	string lisflood_DEM_file 			-> {"inputs/"+"LittoSIM_GEN_"+application_name+"_DEM"+ timestamp + ".asc"}  ; // DEM file 
	string lisflood_rugosityGrid_file 	-> {"inputs/"+"LittoSIM_GEN_"+application_name+"_n" + timestamp + ".asc"}; // rugosity file
	string lisflood_bat_file 			<- flooding_def["LISFLOOD_BAT_FILE"] ; //  Lisflood executable
	
	// variables for Lisflood calculs 
	map<string,string> list_flooding_events ;  // list of submersions of a round
	string floodEventType;
	int lisfloodReadingStep <- 9999999; // to indicate to which step of Lisflood results, the current cycle corresponds // lisfloodReadingStep = 9999999 it means that there is no Lisflood result corresponding to the current cycle 
	string timestamp 		<- ""; // used to specify a unique name to the folder of flooding results
	string flood_results 	<- "";   //  text of flood results per district // saved as a txt file
	
	// parameters for saving submersion results
	string results_rep 			<- results_lisflood_rep+ "/results"+EXPERIMENT_START_TIME; // folder to save main model results
	string shape_export_filePath -> {results_rep+"/results_SHP_Tour"+game_round+".shp"}; //	shapefile to save cells
	string log_export_filePath 	<- results_rep+"/log_"+machine_time+".csv"; 	// file to save user actions (main model and players actions)  
	
	// operation variables
	geometry shape 				<- envelope(emprise_shape); // world geometry
	float EXPERIMENT_START_TIME <- machine_time; // machine time at simulation initialization
	int messageID 				<- 0; // network communication
	geometry all_flood_risk_area; // geometry agrregating risked area polygons
	geometry all_protected_area; // geometry agrregating protected area polygons	
	
	// budget tables to draw evolution graphs
	list<list<int>> districts_budgets <- [[],[],[],[]];
	
	// population dynamics
	int new_comers_still_to_dispatch <- 0;
	
	// Natural, Urbanized, Authorized Urbanization, Agricultural, Urbanized subsidized, Authorized Urbanization subsidized
    list<string> lu_type_names 	<- ["","N","U","","AU","A","Us","AUs"];
	
	// other variables 
	bool show_max_water_height	<- false ;// defines if the water_height displayed on the map should be the max one or the current one
	string stateSimPhase 		<- SIM_NOT_STARTED; // state variable of current simulation state 
	int game_round 				<- 0;
	list<rgb> listC 			<- brewer_colors("YlOrRd", 8);
	list<District> districts_in_game;
	
	init{
		create Data_retreive;
		// Create GIS agents
		create District from: districts_shape with: [district_code::string(read("dist_code")),
													 district_name::string(read("dist_sname")),
													id::int(read("player_id"))]{
			write "" + langs_def at 'MSG_COMMUNE' at configuration_file["LANGUAGE"] + " " + district_name + "("+district_code+")" + " "+id;
		}
		districts_in_game <- (District where (each.id > 0)) sort_by (each.id);
		
		create Coastal_Defense from: coastal_defenses_shape with: [dike_id::int(read("object_id")),
										type::string(read("type")), status::string(read("status")),
										alt::float(get("alt")), height::float(get("height")), district_code::string(read("dist_code"))];
		
		create Protected_Area from: protected_areas_shape with: [name::string(read("site_code"))];
		all_protected_area <- union(Protected_Area);
		create Road from: roads_shape;
		create Flood_Risk_Area from: rpp_area_shape;
		all_flood_risk_area <- union(Flood_Risk_Area);
		create Coastal_Border_Area from: coastline_shape { shape <-  shape + coastBorderBuffer #m; }
		create Inland_Dike_Area from: contour_neg_100m_shape;
		
		create Land_Use from: land_use_shape with: [id::int(read("unit_id")), lu_code::int(read("unit_code")),
													population::int(get("unit_pop")), exp_cost:: int(get("exp_cost"))]{
			lu_name <- lu_type_names[lu_code];
			my_color <- cell_color();
			if lu_name = "U" and population = 0 { population <- MIN_POP_AREA;	}
			if lu_name = "AU" {	AU_to_U_counter <- flip(0.5)?1:0;	not_updated <- true;	}
		}
		
		// Create Network agents
		if activemq_connect {
			create Network_round_manager;
			create Network_listener_to_leader;
			create Network_player;
			create Network_activated_lever;
		}
		
		loop i from: 0 to: (length(listC)-1) {	listC[i] <- blend (listC[i], #red , 0.9);	}
		do init_buttons;
		stateSimPhase <- SIM_NOT_STARTED;
		do addElementIn_list_flooding_events ("Initial submersion","results");
		
		do load_rugosity;
		ask Land_Use {	cells <- Cell overlapping self;	}
		ask districts_in_game{
			LUs <- Land_Use overlapping self;
			cells <- Cell overlapping self;
			budget <- int(self.current_population() * tax_unit * (1 +  pctBudgetInit/100));
			write district_name +" "+ langs_def at 'MSG_INITIAL_BUDGET' at configuration_file["LANGUAGE"] + " : " + budget;
			do calculate_indicators_t0;
		}
		ask Coastal_Defense {	do init_coastal_def;	}

	}
	//------------------------------ End of init -------------------------------//
	 	
	int getMessageID{
 		messageID<- messageID +1;
 		return messageID;
 	} 	
	 	
	int delayOfAction (int action_code){
		int rslt <- 9999;
		loop i from:0 to: (length(actions_def) /3) - 1 {
			if ((int(actions_def at {1,i})) = action_code)
			 {rslt <- int(actions_def at {2,i});}
		}
		return rslt;
	}
	 
	int entityTypeCodeOfAction (int action_code){
		string rslt <- "";
		loop i from:0 to: (length(actions_def) /3) - 1 {
			if ((int(actions_def at {1,i})) = action_code)
			 {rslt <- actions_def at {4,i};}
		}
		switch rslt {
			match "COAST_DEF" {return ENTITY_TYPE_CODE_COAST_DEF; }
			match "LU" 		  {return ENTITY_TYPE_CODE_LU;		  }
			default 		  {return 0;						  }
		}
	} 
	
	int new_comers_to_dispatch 	 {
		return round(sum(District where (each.id > 0) accumulate (each.current_population())) * ANNUAL_POP_GROWTH_RATE);
	}

	action new_round{
		if save_shp {	do save_cells_as_shp_file;	}
		write MSG_NEW_ROUND + " " + (game_round +1);
		if game_round != 0 {
			ask Coastal_Defense where (each.type != DUNE) {  do degrade_dike_status;  }
		   	ask Coastal_Defense where (each.type  = DUNE) {  do evolve_dune_status;	  }
			new_comers_still_to_dispatch <- new_comers_to_dispatch() ;
			ask shuffle(Land_Use) 			 { pop_updated <- false; do evolve_AU_to_U;  }
			ask shuffle(Land_Use) 			 { do evolve_U_densification; 				 }
			ask shuffle(Land_Use) 			 { do evolve_U_standard; 					 } 
			ask District where (each.id > 0) { do calculate_taxes;						 }
		}
		else {
			stateSimPhase <- SIM_GAME;
			write stateSimPhase;
		}
		game_round <- game_round + 1;
		ask District 				 	{	do inform_new_round;			} 
		ask Network_listener_to_leader  {	do informLeader_round_number;	}
		do save_budget_data;
		write MSG_GAME_DONE + " !";
	} 	
	
	int district_id(string xx){ // FIXME quoi ?!!
		District m <- District first_with (each.network_name = xx);
		if(m = nil){
			m <- (District first_with (xx contains each.district_code));
			m.network_name <- xx;
		}
		return m.id;
	}

	reflex show_flood_stats when: stateSimPhase = SIM_SHOWING_FLOOD_STATS {// fin innondation
		// affichage des résultats 
		write flood_results;
		save flood_results to: lisfloodRelativePath+results_rep+"/flood_results-"+machine_time+"-Tour"+ game_round +".txt" type: "text";

		map values <- user_input([(MSG_OK_CONTINUE):: ""]);
		
		// remise à zero des hauteurs d'eau
		loop r from: 0 to: nb_rows -1{	loop c from:0 to: nb_cols -1 {Cell[c,r].water_height <- 0.0;}}
		
		// cancel dikes ruptures				
		ask Coastal_Defense { if rupture = 1 { do remove_rupture; } }
		
		// redémarage du jeu
		if game_round = 0{
			stateSimPhase <- SIM_NOT_STARTED;
			write stateSimPhase;
		}
		else{
			stateSimPhase <- SIM_GAME;
			write stateSimPhase + " - "+ langs_def at 'MSG_ROUND' at configuration_file["LANGUAGE"] +" "+ game_round;
		}
	}
	
	reflex calculate_flood_stats when: stateSimPhase = SIM_CALCULATING_FLOOD_STATS{// end of an inundation
		do calculate_districts_results; // calculating results
		stateSimPhase <- SIM_SHOWING_FLOOD_STATS;
		write stateSimPhase;
	}
	
	// reading inundation files
	reflex show_lisflood when: stateSimPhase = SIM_SHOWING_LISFLOOD	{	do readLisflood;	}
	
	action replay_flood_event{
		string txt;
		int i <-1;
		loop aK over: list_flooding_events.keys{
			txt<- txt + "\n"+i+" :"+aK;
			i <-i +1;
		}
		map values <- user_input((MSG_SUBMERSION_NUMBER) + " " + txt,[(MSG_NUMBER)+ " :" :: "0"]);
		map<string, unknown> msg <-[];
		i <- int(values[(MSG_NUMBER)+ " :"]);
		if i=0 or i > length(list_flooding_events.keys){return;}
				
		string replayed_flooding_event  <- (list_flooding_events.keys)[i-1] ;
		write replayed_flooding_event;
		loop r from: 0 to: nb_rows -1  { loop c from:0 to: nb_cols -1 {Cell[c,r].max_water_height <- 0.0; } } // remise à zero de max_water_height
		set lisfloodReadingStep <- 0;
		results_lisflood_rep <- list_flooding_events at replayed_flooding_event;
		stateSimPhase <- SIM_SHOWING_LISFLOOD; write stateSimPhase;
	}
		
	action launchFlood_event{
		if game_round = 0 {
			map values <- user_input([(MSG_SIM_NOT_STARTED) :: ""]);
	     	write stateSimPhase;
		}
		// excuting Lisflood
		if game_round != 0 {
			do new_round;
			loop r from: 0 to: nb_rows -1  {
				loop c from:0 to: nb_cols -1 {
					Cell[c,r].max_water_height <- 0.0;  // reset of max_water_height
				}
			}
			ask Coastal_Defense {	do calculate_rupture;		}
			stateSimPhase <- SIM_EXEC_LISFLOOD;
			write stateSimPhase;
			do executeLisflood;
		} 
		lisfloodReadingStep <- 0;
		stateSimPhase <- SIM_SHOWING_LISFLOOD;
		write stateSimPhase;
	}

	action addElementIn_list_flooding_events (string sub_name, string sub_rep){
		put sub_rep key: sub_name in: list_flooding_events;
		ask Network_round_manager{
			do add_element(sub_name,sub_rep);
		}
	}
		
	action executeLisflood{
		timestamp <- "_R"+ game_round + "_t"+machine_time ;
		results_lisflood_rep <- "results"+timestamp;
		do save_dem;  
		do save_rugosityGrid;
		do save_lf_launch_files;
		do addElementIn_list_flooding_events("Submersion Tour "+ game_round ,results_lisflood_rep);
		save "directory created by littoSIM Gama model" to: lisfloodRelativePath+results_lisflood_rep+"/readme.txt" type: "text";// need to create the lisflood results directory because lisflood cannot create it buy himself
		ask Network_listener_to_leader{
			do execute command:"cmd /c start "+lisfloodPath+lisflood_bat_file; }
 	}
 		
	action save_lf_launch_files {
		save ("DEMfile         "+lisfloodPath+lisflood_DEM_file+"\nresroot         res\ndirroot         results\nsim_time        52200\ninitial_tstep   10.0\nmassint         100.0\nsaveint         3600.0\n#checkpoint     0.00001\n#overpass       100000.0\n#fpfric         0.06\n#infiltration   0.000001\n#overpassfile   buscot.opts\nmanningfile     "+lisfloodPath+lisflood_rugosityGrid_file+"\n#riverfile      buscot.river\nbcifile         "+lisfloodPath+"oleron2016.bci\nbdyfile         "+lisfloodPath+lisflood_bdy_file+"\n#weirfile       buscot.weir\nstartfile       "+lisfloodPath+"oleron.start\nstartelev\n#stagefile      buscot.stage\nelevoff\n#depthoff\n#adaptoff\n#qoutput\n#chainageoff\nSGC_enable\n") rewrite: true to: lisfloodRelativePath+lisflood_par_file type: "text"  ;
		save (lisfloodPath+"lisflood.exe -dir "+ lisfloodPath+results_lisflood_rep +" "+(lisfloodPath+lisflood_par_file)) rewrite: true  to: lisfloodRelativePath+lisflood_bat_file type: "text" ;
	}       

	action save_dem {	save Cell to: lisfloodRelativePath + lisflood_DEM_file type: "asc";	}
	action save_cells_as_shp_file {	save Cell type:"shp" to: shape_export_filePath with: [soil_height::"SOIL_HEIGHT", water_height::"WATER_HEIGHT"];	}
	action save_budget_data{
		loop ix from: 1 to: 4 {	add (District first_with(each.id = ix)).budget to: districts_budgets[ix-1];	}
	}	

	action save_rugosityGrid {
		string filename <- lisfloodRelativePath+lisflood_rugosityGrid_file;
		save 'ncols         631\nnrows         906\nxllcorner     364927.14666668\nyllcorner     6531972.5655556\ncellsize      20\nNODATA_value  -9999' rewrite: true to: filename type:"text";
		loop j from: 0 to: nb_rows- 1 {
			string text <- "";
			loop i from: 0 to: nb_cols - 1 {	text <- text + " "+ Cell[i,j].rugosity;	}
			save text to: filename rewrite: false ;
		}
	}
	   
	action readLisflood{  
	 	string nb <- string(lisfloodReadingStep);
		loop i from: 0 to: 3-length(nb) { nb <- "0"+nb; }
		string fileName <- lisfloodRelativePath+results_lisflood_rep+"/res-"+ nb +".wd";
		write "lisfloodRelativePath " + lisfloodRelativePath;
		write "results_lisflood_rep " + results_lisflood_rep;
		write "nb  " + nb;
		if file_exists (fileName){
			write fileName;
			file lfdata <- text_file(fileName) ;
			loop r from: 6 to: length(lfdata) -1 {
				string l <- lfdata[r];
				list<string> res <- l split_with "\t";
				loop c from: 0 to: length(res) - 1{
					float w <- float(res[c]);
					if w > Cell[c,r-6].max_water_height {Cell[c,r-6].max_water_height <-w;}
					Cell[c,r-6].water_height <- w;}}	
	        lisfloodReadingStep <- lisfloodReadingStep +1;
	     }
	     else{ // end of flooding
     		lisfloodReadingStep <-  9999999;
     		if nb = "0000" {
     			map values <- user_input([(MSG_NO_FLOOD_FILE_EVENT) :: ""]);
     			stateSimPhase <- SIM_GAME;
     			write stateSimPhase + " - "+langs_def at 'MSG_ROUND' at configuration_file["LANGUAGE"]+" "+ game_round;
     		}
     		else{	stateSimPhase <- SIM_CALCULATING_FLOOD_STATS; write stateSimPhase; }	}
	}
	
	action load_rugosity{
		file rug_data <- text_file(RUGOSITE_PAR_DEFAUT) ;
		loop r from: 6 to: length(rug_data) -1 {
			string l <- rug_data[r];
			list<string> res <- l split_with " ";
			loop c from: 0 to: length(res) - 1 { Cell[c,r-6].rugosity <- float(res[c]);} }	
	}
	
	action calculate_districts_results{
		string text <- "";
			ask ((District where (each.id > 0)) sort_by (each.id)){
				int tot <- length(cells) ;
				int myid <-  self.id; 
				int U_0_5 <-0;		int U_1 <-0;		int U_max <-0;
				int Us_0_5 <-0;		int Us_1 <-0;		int Us_max <-0;
				int Udense_0_5 <-0;	int Udense_1 <-0;	int Udense_max <-0;
				int AU_0_5 <-0;		int AU_1 <-0;		int AU_max <-0;
				int A_0_5 <-0;		int A_1 <-0;		int A_max <-0;
				int N_0_5 <-0;		int N_1 <-0;		int N_max <-0;
				
				ask LUs{
					ask cells {
						if max_water_height > 0{
							switch myself.lu_name{ //"U","Us","AU","N","A"    -> et  "AUs" impossible normallement
								match "AUs" {
									write "STOP :  AUs " + langs_def at 'MSG_IMPOSSIBLE_NORMALLY' at configuration_file["LANGUAGE"];
								}
								match "U" {
									if max_water_height <= 0.5 					{
										U_0_5 <- U_0_5 +1;
										if myself.density_class = POP_DENSE 	{	Udense_0_5 <- Udense_0_5 +1;	}
									}
									if between (max_water_height ,0.5, 1.0) 	{
										U_1 <- U_1 +1;
										if myself.density_class = POP_DENSE 	{	Udense_1 <- Udense_1 +1;		}
									}
									if max_water_height >= 1					{
										U_max <- U_max +1 ;
										if myself.density_class = POP_DENSE 	{	Udense_0_5 <- Udense_0_5 +1;	}
									}
								}
								match "Us" {
									if max_water_height <= 0.5 				{	Us_0_5 <- Us_0_5 +1;			}
									if between (max_water_height ,0.5, 1.0) {	Us_1 <- Us_1 +1;				}
									if max_water_height >= 1				{	Us_max <- Us_max +1 ;			}
								}
								match "AU" {
									if max_water_height <= 0.5 				{	AU_0_5 <- AU_0_5 +1;			}
									if between (max_water_height ,0.5, 1.0) {	AU_1 <- AU_1 +1;				}
									if max_water_height >= 1.0 				{	AU_max <- AU_max +1 ;			}
								}
								match "N"  {
									if max_water_height <= 0.5 				{	N_0_5 <- N_0_5 +1;				}
									if between (max_water_height ,0.5, 1.0) {	N_1 <- N_1 +1;					}
									if max_water_height >= 1.0 				{	N_max <- N_max +1 ;				}
								}
								match "A" {
									if max_water_height <= 0.5 				{	A_0_5 <- A_0_5 +1;				}
									if between (max_water_height ,0.5, 1.0) {	A_1 <- A_1 +1;					}
									if max_water_height >= 1.0 				{	A_max <- A_max +1 ;				}
								}	
							}
						}
					}
				}
				U_0_5c <- U_0_5 * 0.04;
				U_1c <- U_1 * 0.04;
				U_maxc <- U_max * 0.04;
				Us_0_5c <- Us_0_5 * 0.04;
				Us_1c <- Us_1 * 0.04;
				Us_maxc <- Us_max * 0.04;
				Udense_0_5c <- Udense_0_5 * 0.04;
				Udense_1c <- Udense_1 * 0.04;
				Udense_maxc <- Udense_max * 0.04;
				AU_0_5c <- AU_0_5 * 0.04;
				AU_1c <- AU_1 * 0.04;
				AU_maxc <- AU_max * 0.04;
				A_0_5c <- A_0_5 * 0.04;
				A_1c <- A_1 * 0.04;
				A_maxc <- A_max * 0.04;
				N_0_5c <- N_0_5 * 0.04;
				N_1c <- N_1 * 0.04;
				N_maxc <- N_max * 0.04;
				text <- text + "Résultats commune " + district_name +"
Surface U innondée : moins de 50cm " + ((U_0_5c) with_precision 1) +" ha ("+ ((U_0_5 / tot * 100) with_precision 1) +"%) | entre 50cm et 1m " + ((U_1c) with_precision 1) +" ha ("+ ((U_1 / tot * 100) with_precision 1) +"%) | plus de 1m " + ((U_maxc) with_precision 1) +" ha ("+ ((U_max / tot * 100) with_precision 1) +"%) 
Surface Us innondée : moins de 50cm " + ((Us_0_5c) with_precision 1) +" ha ("+ ((Us_0_5 / tot * 100) with_precision 1) +"%) | entre 50cm et 1m " + ((Us_1c) with_precision 1) +" ha ("+ ((Us_1 / tot * 100) with_precision 1) +"%) | plus de 1m " + ((Us_maxc) with_precision 1) +" ha ("+ ((Us_max / tot * 100) with_precision 1) +"%) 
Surface Udense innondée : moins de 50cm " + ((Udense_0_5c) with_precision 1) +" ha ("+ ((Udense_0_5 / tot * 100) with_precision 1) +"%) | entre 50cm et 1m " + ((Udense_1 * 0.04) with_precision 1) +" ha ("+ ((Udense_1 / tot * 100) with_precision 1) +"%) | plus de 1m " + ((Udense_max * 0.04) with_precision 1) +" ha ("+ ((Udense_max / tot * 100) with_precision 1) +"%) 
Surface AU innondée : moins de 50cm " + ((AU_0_5c) with_precision 1) +" ha ("+ ((AU_0_5 / tot * 100) with_precision 1) +"%) | entre 50cm et 1m " + ((AU_1c) with_precision 1) +" ha ("+ ((AU_1 / tot * 100) with_precision 1) +"%) | plus de 1m " + ((AU_maxc) with_precision 1) +" ha ("+ ((AU_max / tot * 100) with_precision 1) +"%) 
Surface A innondée : moins de 50cm " + ((A_0_5c) with_precision 1) +" ha ("+ ((A_0_5 / tot * 100) with_precision 1) +"%) | entre 50cm et 1m " + ((A_1c) with_precision 1) +" ha ("+ ((A_1 / tot * 100) with_precision 1) +"%) | plus de 1m " + ((A_maxc) with_precision 1) +" ha ("+ ((A_max / tot * 100) with_precision 1) +"%) 
Surface N innondée : moins de 50cm " + ((N_0_5c) with_precision 1) +" ha ("+ ((N_0_5 / tot * 100) with_precision 1) +"%) | entre 50cm et 1m " + ((N_1c) with_precision 1) +" ha ("+ ((N_1 / tot * 100) with_precision 1) +"%) | plus de 1m " + ((N_maxc) with_precision 1) +" ha ("+ ((N_max / tot * 100) with_precision 1) +"%) 
--------------------------------------------------------------------------------------------------------------------
" ;	
			}
			flood_results <-  text;
				
			write langs_def at 'MSG_FLOODED_AREA_DISTRICT' at configuration_file["LANGUAGE"];
			ask ((District where (each.id > 0)) sort_by (each.id)){
				flooded_area <- (U_0_5c + U_1c + U_maxc + Us_0_5c + Us_1c + Us_maxc + AU_0_5c + AU_1c + AU_maxc + N_0_5c + N_1c + N_maxc + A_0_5c + A_1c + A_maxc) with_precision 1 ;
					add flooded_area to: data_flooded_area; 
					write ""+ district_name + " : " + flooded_area +" ha";

					totU <- (U_0_5c + U_1c + U_maxc) with_precision 1 ;
					totUs <- (Us_0_5c + Us_1c + Us_maxc ) with_precision 1 ;
					totUdense <- (Udense_0_5c + Udense_1c + Udense_maxc) with_precision 1 ;
					totAU <- (AU_0_5c + AU_1c + AU_maxc) with_precision 1 ;
					totN <- (N_0_5c + N_1c + N_maxc) with_precision 1 ;
					totA <-  (A_0_5c + A_1c + A_maxc) with_precision 1 ;	
					add totU to: data_totU;
					add totUs to: data_totUs;
					add totUdense to: data_totUdense;
					add totAU to: data_totAU;
					add totN to: data_totN;
					add totA to: data_totA;	
			}
	}
	
	// creating buttons
 	action init_buttons{
		create Buttons{
			nb_button <- 0;					command 	 <- "ONE_STEP";
			shape <- square(button_size);	location <- { 1000,1000 };
			my_icon <- image_file("../images/icones/one_step.png");
		}
		create Buttons{
			nb_button <- 3; 				command	 <- "HIGH_FLOODING";
			shape <- square(button_size);	location <- { 5000,1000 };
			my_icon <- image_file("../images/icones/launch_lisflood.png");
		}
		create Buttons{
			nb_button <- 5;					command	 <- "LOW_FLOODING";
			shape <- square(button_size);	location <- { 7000,1000 };
			my_icon <- image_file("../images/icones/launch_lisflood_small.png");
		}
		create Buttons{
			nb_button <- 6;					command 	 <- "REPLAY_FLOODING";
			shape <- square(button_size);	location <- { 9000,1000 };
			my_icon <- image_file("../images/icones/replay_flooding.png");
		}
		create Buttons{
			nb_button <- 4;					command 	 <- "SHOW_LU_GRID";
			shape <- square(850);			location <- { 800,14000 };
			my_icon <- image_file("../images/icones/sans_quadrillage.png");
			is_selected <- false;
		}
		create Buttons{
			nb_button <- 7;					command	 <- "SHOW_MAX_WATER_HEIGHT";
			shape <- square(850);			location <- { 1800,14000 };
			my_icon <- image_file("../images/icones/max_water_height.png");
			is_selected <- false;
		}
	}
	
	//clearing buttons selection
    action clear_selected_button{	ask Buttons{	self.is_selected <- false;	}	}
	
	// the four buttons of game master control display 
    action button_click_master_control{
		point loc <- #user_location;
		list<Buttons> buttonsMaster <- ( Buttons where (each distance_to loc < MOUSE_BUFFER));
		if(length(buttonsMaster) > 0){
			do clear_selected_button;
			ask(buttonsMaster){
				is_selected <- true;
				switch nb_button 	{
					match 		0   { 							ask world {	do new_round;		    } }
					match_one [3, 5]{ floodEventType <- command;ask world { do launchFlood_event;   } }
					match 6			{ 							ask world { do replay_flood_event();} }
				}
			}
		}
	}
	
	// the two buttons of the first map display
	action button_click_map {
		point loc <- #user_location;
		Buttons a_button <- first((Buttons where (each distance_to loc < MOUSE_BUFFER)));
		if a_button != nil{
			ask a_button{
				is_selected <- not(is_selected);
				if(a_button.nb_button = 4){
					my_icon		<-  is_selected ? image_file("../images/icones/avec_quadrillage.png") : image_file("../images/icones/sans_quadrillage.png");
				}else if(a_button.nb_button = 7){
					show_max_water_height <- is_selected;
				}
			}
		}
	}
	
	rgb color_of_water_height (float aWaterHeight){
		if 		aWaterHeight  	<= 0.5	{	return rgb (200,200,255);	}
		else if aWaterHeight  	<= 1  	{	return rgb (115,115,255);	}
		else if aWaterHeight	<= 2  	{	return rgb (65,65,255);		}
		else 							{	return rgb (30,30,255);		}
	}
}
//------------------------------ End of global -------------------------------//

//---------------------------- Species definiton -----------------------------//
 
species Data_retreive skills:[network] schedules:[] { // Receiving and applying players actions
	init {
		write langs_def at 'MSG_START_SENDER' at configuration_file["LANGUAGE"];
		do connect to: SERVER with_name: GAME_MANAGER+"_retreive";
	}
	
	action send_data_to_district (District d){
		write "" + langs_def at 'MSG_SEND_DATA_TO' at configuration_file["LANGUAGE"] +" "+ d.network_name;
		ask d {	do inform_budget_update(); }
		do retreive_coastal_defense(d);
		do retreive_LU(d);
		do retreive_action_done(d);
		do retreive_activated_lever(d);
	}
	
	action retreive_coastal_defense(District d){	
		loop tmp over: Coastal_Defense where(each.district_code = d.district_code){
			write "" + langs_def at 'MSG_SEND_TO' at configuration_file["LANGUAGE"] +" "+ d.network_name + "_retreive " + tmp.build_map_from_attributes();
			do send to: d.network_name +"_retreive" contents: tmp.build_map_from_attributes();
		}
	}
	
	action retreive_LU (District d){
		loop tmp over: d.LUs{
			write "" + langs_def at 'MSG_SEND_TO' at configuration_file["LANGUAGE"] + " " + d.network_name + "_retreive " + tmp.build_map_from_attributes();
			do send to: d.network_name +"_retreive" contents: tmp.build_map_from_attributes();
		}
	}

	action retreive_action_done(District d){
		loop tmp over: Player_Action where(each.district_code = d.district_code){
			write "" + langs_def at 'MSG_SEND_TO' at configuration_file["LANGUAGE"] + " " + d.network_name+ "_retreive " + tmp.build_map_from_attributes();
			do send to: d.network_name+"_retreive" contents: tmp.build_map_from_attributes();
		}
	}
	
	action retreive_activated_lever(District d){
		loop tmp over: Activated_lever where(each.my_map[DISTRICT_CODE] = d.district_code) {
			write "" + langs_def at 'MSG_SEND_TO' at configuration_file["LANGUAGE"] + " " + d.network_name + "_retreive " + tmp.my_map;
			do send to: d.network_name+"_retreive" contents: tmp.my_map;
		}
	}
	
	action lock_window(District d, bool are_allowed){
		string val <- are_allowed=true?"UN_LOCKED":"LOCKED";
		map<string,string> me <- ["OBJECT_TYPE"::"lock_unlock",
								  "WINDOW_STATUS"::val];
		do send to: d.network_name+"_retreive" contents: me;
	}
}
//------------------------------ End of Data_retrieve -------------------------------//

species Player_Action schedules:[]{
	string id;
	int element_id;
	geometry element_shape;
	string district_code<-"";
	int command <- -1 on_change: {label <- world.labelOfAction(command);};
	int command_round<- -1;
	string label <- "no name";
	int initial_application_round <- -1;
	int round_delay -> {activated_levers sum_of int(each.my_map["nb_rounds_delay"])} ; // nb rounds of delay
	int actual_application_round -> {initial_application_round+round_delay};
	bool is_delayed ->{round_delay>0} ;
	float cost <- 0.0;
	int added_cost -> {activated_levers sum_of int(each.my_map["added_cost"])} ;
	float actual_cost -> {cost+added_cost};
	bool has_added_cost ->{added_cost>0} ;
	bool is_sent <-true;
	bool is_sent_to_leader <-false;
	bool is_applied <- false;
	bool should_be_applied ->{game_round >= actual_application_round} ;
	string action_type <- DIKE ; //can be "dike" or "PLU"
	string previous_lu_name <-"";  // for PLU action
	bool isExpropriation <- false; // for PLU action
	bool inProtectedArea <- false; // for dike action
	bool inCoastBorderArea <- false; // for PLU action // c'est la bande des 400 m par rapport au trait de cote
	bool inRiskArea <- false; // for PLU action / Ca correspond à la zone PPR qui est un shp chargé
	bool isInlandDike <- false; // for dike action // ce sont les rétro-digues
	bool is_alive <- true;
	list<Activated_lever> activated_levers <-[];
	bool shouldWaitLeaderToActivate <- false;
	int length_def_cote<-0;
	bool a_lever_has_been_applied<- false;
	
	
	map<string,string> build_map_from_attributes{
		map<string,string> res <- ["OBJECT_TYPE"::"action_done", "id"::id, "element_id"::string(element_id),
			"command"::string(command), "label"::label, "cost"::string(cost),
			"initial_application_round"::string(initial_application_round), "isInlandDike"::string(isInlandDike),
			"inRiskArea"::string(inRiskArea), "inCoastBorderArea"::string(inCoastBorderArea), "isExpropriation"::string(isExpropriation),
			"inProtectedArea"::string(inProtectedArea), "previous_lu_name"::previous_lu_name, "action_type"::action_type,
			"locationx"::string(location.x), "locationy"::string(location.y), "is_applied"::string(is_applied), "is_sent"::string(is_sent),
			"command_round"::string(command_round), "element_shape"::string(element_shape), "length_def_cote"::string(length_def_cote),
			"a_lever_has_been_applied"::string(a_lever_has_been_applied)];
			put district_code at: DISTRICT_CODE in: res;
			int i <- 0;
			loop pp over:element_shape.points{
				put string(pp.x) key: "locationx"+i in: res;
				put string(pp.y) key: "locationy"+i in: res;
				i <- i + 1;
			}
		return res;
	}
	
	aspect base{
		int indx <- Player_Action index_of self;
		float y_loc <- float((indx +1)  * font_size) ;
		float x_loc <- float(font_interleave + 12* (font_size+font_interleave));
		float x_loc2 <- float(font_interleave + 20* (font_size+font_interleave));
		shape <- rectangle({font_size+2*font_interleave,y_loc},{x_loc2,y_loc+font_size/2} );
		draw shape color:#white;
		string txt <-  ""+world.table_correspondance_insee_com_nom_rac at (district_code)+": "+ label;
		txt <- txt +" ("+string(initial_application_round-game_round)+")"; 
		draw txt at:{font_size+2*font_interleave,y_loc+font_size/2} size:font_size#m color:#black;
		draw "    "+ round(cost) at:{x_loc,y_loc+font_size/2} size:font_size#m color:#black;	
	}
	
	Coastal_Defense create_dike(Player_Action act){
		int next_dike_id <- max(Coastal_Defense collect(each.dike_id))+1;
		create Coastal_Defense number:1 returns:new_dikes{
			dike_id <- next_dike_id;
			district_code <- act.district_code;
			shape <- act.element_shape;
			location <- act.location;
			type <- BUILT_DIKE_TYPE ;
			status <- BUILT_DIKE_STATUS;
			height <- BUILT_DIKE_HEIGHT;	
			cells <- Cell overlapping self;
		}
		act.element_id <- first(new_dikes).dike_id;
		return first(new_dikes);
	}
}
//------------------------------ End of Player_Action -------------------------------//

species Network_player skills:[network]{
	
	init{	do connect to: SERVER with_name: GAME_MANAGER;	}
	
	reflex wait_message when: activemq_connect{
		loop while: has_more_message(){
			message msg <- fetch_message();
			string m_sender <- msg.sender;
			map<string, unknown> m_contents <- msg.contents;
			if(m_sender != GAME_MANAGER ){
				if(m_contents["stringContents"] != nil){
					write "" + langs_def at 'MSG_READ_MESSAGE' at configuration_file["LANGUAGE"] + " : " + m_contents["stringContents"];
					list<string> data <- string(m_contents["stringContents"]) split_with COMMAND_SEPARATOR;
					
					if(int(data[0]) = CONNECTION_MESSAGE){ // a client district wants to connect
						int id_dist <- world.district_id (m_sender);
						ask(District where(each.id = id_dist)){
							do inform_current_round;
							do inform_budget_update;
						}
						write "" + langs_def at 'MSG_CONNECTION_FROM' at configuration_file["LANGUAGE"] + " " + m_sender + " " + id_dist;
					}
					else if(int(data[0]) = REFRESH_ALL){
						int id_dist <- world.district_id(m_sender);
						write " Update ALL !!!! " + id_dist + " ";
						District d <- first(District where(each.id = id_dist));
						ask first(Data_retreive) {
							do send_data_to_district(d);
						}
					}
					else{
						if(game_round > 0) {
							write "" + langs_def at 'MSG_READ_ACTION' at configuration_file["LANGUAGE"] + " " + m_contents["stringContents"];
							do read_action(string(m_contents["stringContents"]), m_sender);
						}
					}
				}
				else{	map<string,unknown> data <- m_contents["objectContent"];	}				
			}				
		}
	}
		
	action read_action(string act, string sender){
		list<string> data <- act split_with COMMAND_SEPARATOR;
		
		if(! (int(data[0]) in ACTION_LIST) ){	return;	}
		
		create Player_Action returns: tmp_agent_list;
		Player_Action new_action <- first(tmp_agent_list);
		ask(new_action){
			self.command <- int(data[0]);
			self.command_round <-game_round; 
			self.id <- data[1];
			self.initial_application_round <- int(data[2]);
			self.district_code <- sender;
			if !(self.command in [REFRESH_ALL]){
				self.element_id <- int(data[3]);
				self.action_type <- data[4];
				self.inProtectedArea <- bool(data[5]);
				self.previous_lu_name <- data[6];
				self.isExpropriation <- bool(data[7]);
				self.cost <- float(data[8]);
				if command = ACTION_CREATE_DIKE{
					point ori <- {float(data[9]),float(data[10])};
					point des <- {float(data[11]),float(data[12])};
					point loc <- {float(data[13]),float(data[14])}; 
					shape <- polyline([ori,des]);
					element_shape <- polyline([ori,des]);
					length_def_cote <- int(element_shape.perimeter);
					location <- loc; 
				}
				else {
					if isExpropriation {	write "" + langs_def at 'MSG_EXPROPRIATION_TRIGGERED' at configuration_file["LANGUAGE"]+" "+self.id;	}
					switch self.action_type {
						match "PLU" {
							Land_Use tmp <- (Land_Use first_with(each.id = self.element_id));
							element_shape <- tmp.shape;
							location <- tmp.location;
						}
						match DIKE {
							element_shape <- (Coastal_Defense first_with(each.dike_id = self.element_id)).shape;
							length_def_cote <- int(element_shape.perimeter);
						}
						default {	write ""+langs_def at 'MSG_ERROR_ACTION_DONE' at configuration_file["LANGUAGE"];	}
					}
				}
				// calcul des attributs qui n'ont pas été calculé au niveau de Participatif et qui ne sont donc pas encore renseigné
				//inCoastBorderArea  // for PLU action // c'est la bande des 400 m par rapport au trait de cote
				//inRiskArea  // for PLU action / Ca correspond à la zone PPR qui est un shp chargé
				//isInlandDike  // for dike action // ce sont les rétro-digues
				if  self.element_shape intersects all_flood_risk_area {	inRiskArea <- true;	}
				if  self.element_shape intersects first(Coastal_Border_Area) {	inCoastBorderArea <- true;	}
				if command = ACTION_CREATE_DIKE and (self.element_shape.centroid overlaps first(Inland_Dike_Area))	{	isInlandDike <- true;	}
				// finallement on recalcul aussi inProtectedArea meme si ca a été calculé au niveau de participatif, car en fait ce n'est pas calculé pour toutes les actions 
				if  self.element_shape intersects all_protected_area {	inProtectedArea <- true;	}
				if(log_user_action){ save ([string(machine_time-EXPERIMENT_START_TIME),self.district_code]+data) to:log_export_filePath rewrite: false type:"csv"; }
			}
		}
		//  le paiement est déjà fait coté commune, lorsque le joueur a validé le panier. On renregistre ici le paiement pour garder les comptes à jour coté serveur
		int id_dis <- world.district_id (new_action.district_code);
		ask District first_with(each.id = id_dis) {	do record_payment_for_player_action(new_action);	}
	}
	
	reflex update_LU  when:length(Land_Use where(each.not_updated)) > 0 {
		list<string> update_messages <-[];
		list<Land_Use> updated_LU <- [];
		ask Land_Use where(each.not_updated){
			string msg <- ""+ACTION_LAND_COVER_UPDATE+COMMAND_SEPARATOR+world.getMessageID() +COMMAND_SEPARATOR+id+COMMAND_SEPARATOR+self.lu_code+COMMAND_SEPARATOR+self.population+COMMAND_SEPARATOR+self.isInDensification;
			update_messages <- update_messages + msg;	
			not_updated <- false;
			updated_LU <- updated_LU + self;
		}
		int i <- 0;
		loop while: i< length(update_messages){
			string msg <- update_messages at i;
			loop d over: District overlapping (updated_LU at i) {
				do send to: d.network_name contents: msg;
			}
			i <- i + 1;
		}
	}
	
	action send_destroy_dike_message(Coastal_Defense a_dike){
		string msg <- "" + ACTION_DIKE_DROPPED + COMMAND_SEPARATOR + world.getMessageID() + COMMAND_SEPARATOR + a_dike.dike_id;
		list<District> cms <- District overlapping a_dike;
		loop cm over:cms{	do send to: cm.network_name contents: msg;	}
	}
	
	action send_created_dike(Coastal_Defense new_dike, Player_Action act){
		new_dike.shape <- act.element_shape;
		point p1 <- first(act.element_shape.points);
		point p2 <- last(act.element_shape.points);
		string msg <- ""+ACTION_DIKE_CREATED+COMMAND_SEPARATOR+world.getMessageID() +
		COMMAND_SEPARATOR+new_dike.dike_id+
		COMMAND_SEPARATOR+p1.x+COMMAND_SEPARATOR+p1.y+
		COMMAND_SEPARATOR+p2.x+COMMAND_SEPARATOR+p2.y+
		COMMAND_SEPARATOR+new_dike.height+
		COMMAND_SEPARATOR+new_dike.type+
		COMMAND_SEPARATOR+new_dike.status+ 
		COMMAND_SEPARATOR+min_dike_elevation(new_dike)+
		COMMAND_SEPARATOR+act.id+
		COMMAND_SEPARATOR+new_dike.location.x+
		COMMAND_SEPARATOR+new_dike.location.y;
		loop d over: District overlapping new_dike{
			do send  to:d.network_name contents:msg;
		}
	}
	
	action acknowledge_application_of_action_done (Player_Action act){
		map<string,string> msg <- ["TOPIC"::"action_done is_applied","id"::act.id];
		put act.district_code  at: DISTRICT_CODE in: msg;
		do send to: act.district_code + "_map_msg" contents:msg;
	}
	
	float min_dike_elevation(Coastal_Defense ovg){	return min(Cell overlapping ovg collect(each.soil_height));	}
	
	reflex update_dike when: length(Coastal_Defense where(each.not_updated)) > 0 {
		list<string> update_messages <-[]; 
		list<Coastal_Defense> update_ouvrage <- [];
		ask Coastal_Defense where(each.not_updated){
			point p1 <- first(self.shape.points);
			point p2 <- last(self.shape.points);
			string msg <- ""+ACTION_DIKE_UPDATE+COMMAND_SEPARATOR+world.getMessageID() +COMMAND_SEPARATOR+self.dike_id+COMMAND_SEPARATOR+p1.x+COMMAND_SEPARATOR+p1.y+COMMAND_SEPARATOR+p2.x+COMMAND_SEPARATOR+p2.y+COMMAND_SEPARATOR+self.height+COMMAND_SEPARATOR+self.type+COMMAND_SEPARATOR+self.status+COMMAND_SEPARATOR+self.ganivelle+COMMAND_SEPARATOR+myself.min_dike_elevation(self);
			update_messages <- update_messages + msg;
			update_ouvrage <- update_ouvrage + self;
			not_updated <- false;
		}
		int i <- 0;
		loop while: i< length(update_messages){
			string msg <- update_messages at i;
			list<District> cms <- District overlapping (update_ouvrage at i);
			loop cm over:cms{	do send to:cm.network_name contents:msg;	}
			i <- i + 1;
		}
	}

	reflex apply_action when: length(Player_Action where (each.is_alive)) > 0{
	//	ask(action_done where(each.should_be_applied and each.is_alive and not(each.shouldWaitLeaderToActivate)))
	// Pour une raison bizarre la ligne au dessus ne fonctionne pas alors que les 2 lignes ci dessous fonctionnent. Pourtant je ne vois aucune difference
		ask Player_Action {
			if should_be_applied and is_alive and !shouldWaitLeaderToActivate {
				string tmp <- self.district_code;
				int idCom <- world.district_id(tmp);
				Player_Action act <- self;
				switch(command){
				match REFRESH_ALL{////  Pourquoi est ce que REFRESH_ALL est une  Player_Action ??
					write " Update ALL !!!! " + idCom+ " "+  world.table_correspondance_insee_com_nom_rac at (district_code);
					string dd <- district_code;
					District cm <- first(District where(each.id=idCom));
					ask first(Data_retreive) {	do send_data_to_district(cm);	}
				}
				match ACTION_CREATE_DIKE{	
					Coastal_Defense new_dike <- create_dike(act);
					ask Network_player	{
						do send_created_dike(new_dike, act);
						do acknowledge_application_of_action_done(act);
					}
					ask(new_dike){ do build_dike; }
				}
				match ACTION_REPAIR_DIKE {
					ask(Coastal_Defense first_with(each.dike_id=element_id)){
						do repaire_dike;
						not_updated <- true;
					}
					ask Network_player{	do acknowledge_application_of_action_done(act);	}		
				}
			 	match ACTION_DESTROY_DIKE {
			 		ask(Coastal_Defense first_with(each.dike_id=element_id)){
						ask Network_player{
							do send_destroy_dike_message(myself);
							do acknowledge_application_of_action_done(act);
						}
						do destroy_dike;
						not_updated <- true;
					}		
				}
			 	match ACTION_RAISE_DIKE {
			 		ask(Coastal_Defense first_with(each.dike_id=element_id)){
						do raise_dike;
						not_updated <- true;
					}
					ask Network_player{	do acknowledge_application_of_action_done(act);	}
				}
				 match ACTION_INSTALL_GANIVELLE {
				 	ask(Coastal_Defense first_with(each.dike_id=element_id)){
						do install_ganivelle ;
						not_updated <- true;
					}
					ask Network_player{	do acknowledge_application_of_action_done(act);	}
				}
			 	match ACTION_MODIFY_LAND_COVER_A {
			 		ask Land_Use first_with(each.id=element_id){
			 		  do modify_LU ("A");
			 		  not_updated <- true;
			 		 }
			 		 ask Network_player{ do acknowledge_application_of_action_done(act); }
			 	}
			 	match ACTION_MODIFY_LAND_COVER_AU {
			 		ask Land_Use first_with(each.id=element_id){
			 		 	do modify_LU ("AU");
			 		 	not_updated <- true;
			 		 }
			 		 ask Network_player{ do acknowledge_application_of_action_done(act); }
			 	}
				match ACTION_MODIFY_LAND_COVER_N {
					ask Land_Use first_with(each.id=element_id){
			 		 	do modify_LU ("N");
			 		 	not_updated <- true;
			 		 }
			 		 ask Network_player{ do acknowledge_application_of_action_done(act); }
			 	}
			 	match ACTION_MODIFY_LAND_COVER_Us {
			 		ask Land_Use first_with(each.id=element_id){
			 		 	do modify_LU ("Us");
			 		 	not_updated <- true;
			 		 }
			 		ask Network_player{
						do acknowledge_application_of_action_done(act);
					}
			 	 }
			 	 match ACTION_MODIFY_LAND_COVER_Ui {
			 		ask Land_Use first_with(each.id=element_id){
			 		 	isInDensification <- true;
			 		 	not_updated <- true;
			 		 }
			 		ask Network_player{	do acknowledge_application_of_action_done(act);	}
			 	 }
			 	match ACTION_MODIFY_LAND_COVER_AUs {
			 		ask Land_Use first_with(each.id=element_id){
			 		 	do modify_LU ("AUs");
			 		 	not_updated <- true;
			 		 }
			 		ask Network_player{	do acknowledge_application_of_action_done(act);	}
			 	}
				}
			is_alive <- false; 
			is_applied <- true;
			}
		}		
	}
}
//------------------------------ End of Network player -------------------------------//

species Network_round_manager skills:[remoteGUI]{
	list<string> mtitle <- list_flooding_events.keys;
	list<string> mfile <- [];
	string selected_action;
	string choix_simu_temp <- nil;
	string choix_simulation <- "Submersion initiale";
	int mround <-0 update:world.game_round;
	 
	init{
		do connect to:SERVER;
		do expose variables:["mtitle","mfile"] with_name:"listdata";
		do expose variables:["mround"] with_name:"current_round";
		do listen with_name:"simu_choisie" store_to:"choix_simu_temp";
		do listen with_name:"littosim_command" store_to:"selected_action";
		do update_submersion_list;
	}
	
	action update_submersion_list{
		loop a over:list_flooding_events.keys{
			mtitle <- mtitle + a;
			mfile <- mfile + (list_flooding_events at a)	;
		}
	}
	
	reflex selected_action when:selected_action != nil{
		write "network_round_manager " + selected_action;
		switch(selected_action){
			match "NEW_ROUND" { ask world {	do new_round; }}
			match "LOCK_USERS" { do lock_unlock_window(true) ; }
			match "UNLOCK_USERS" { do lock_unlock_window(false) ;}
			match_one ["HIGH_FLOODING","LOW_FLOODING"] {
				floodEventType <- selected_action ;
				ask world {	do launchFlood_event;	}
			}
		}
		selected_action <- nil;
	}
	
	reflex show_submersion when: choix_simu_temp!=nil{
		write "network_round_manager : "+ langs_def at 'MSG_SIMULATION_CHOICE' at configuration_file["LANGUAGE"] +" " + choix_simu_temp;
		choix_simulation <- choix_simu_temp;
		choix_simu_temp <-nil;
	}
	
	action lock_unlock_window(bool value){
		Data_retreive agt <- first(Data_retreive);
		ask District{	ask agt {	do lock_window(myself,value);	}	}
	}
	
	action add_element(string nom_submersion, string path_to_see){	do update_submersion_list;	}
}
//------------------------------ End of Network_round_manager -------------------------------//

species Activated_lever {
	Player_Action act_done;
	float activation_time;
	bool applied <- false;
	
	// contains attributes sent through network
	map<string, string> my_map <- [];
	
	action init_from_map(map<string, string> m ){
		my_map <- m;
		put ACTIVATED_LEVER at: "OBJECT_TYPE" in: my_map;
	}
}
//------------------------------ End of Activated_lever -------------------------------//

species Network_activated_lever skills:[network]{
	
	init{ do connect to:SERVER with_name: ACTIVATED_LEVER;	}
	
	reflex wait_message{
		loop while:has_more_message(){
			message msg <- fetch_message();
			string m_sender <- msg.sender;
			map<string, string> m_contents <- msg.contents;
			if empty(Activated_lever where (int(each.my_map["id"]) = int(m_contents["id"]))){
				create Activated_lever{
					do init_from_map(m_contents);
					act_done <- Player_Action first_with (each.id =  my_map["act_done_id"]);
					District d <- District first_with (each.district_code = district_code);
					d.budget <-d.budget -  int(my_map["added_cost"]); 
					add self to:act_done.activated_levers;
					act_done.a_lever_has_been_applied<- true;
				}
			}			
		}	
	}
}
//------------------------------ End of Network_activated_lever -------------------------------//

species Network_listener_to_leader skills:[network]{
	
	init{	do connect to:SERVER with_name: LISTENER_TO_LEADER;	}
	
	reflex wait_message {
		loop while:has_more_message(){
			message msg <- fetch_message();
			map<string, unknown> m_contents <- msg.contents;
			string cmd <- m_contents[LEADER_COMMAND];
			write "command " + cmd;
			switch(cmd){
				match SUBSIDIZE{
					string district_code <- m_contents[DISTRICT_CODE];
					int amount <- int(m_contents[AMOUNT]);
					District d <- District first_with(each.district_code=district_code);
					d.budget <- d.budget + amount;
				}
				match COLLECT_REC{
					string district_code <- m_contents[DISTRICT_CODE];
					int amount <- int(m_contents[AMOUNT]); 
					District d <- District first_with(each.district_code=district_code);
					d.budget <- d.budget - amount;
				}
				match ASK_NUM_ROUND 		 {	do informLeader_round_number;	}
				match ASK_INDICATORS_T0 	 {	do informLeader_indicators_t0;	}
				match RETREIVE_ACTION_DONE	 {	ask Player_Action {is_sent_to_leader <- false ; } }
				match ACTION_DONE_SHOULD_WAIT_LEVER_TO_ACTIVATE {
					Player_Action aAct <- Player_Action first_with (each.id = string(m_contents[ACTION_DONE_ID]));
					write "msg shouldWait on " + aAct;
					aAct.shouldWaitLeaderToActivate <- bool(m_contents[ACTION_DONE_SHOULD_WAIT_LEVER_TO_ACTIVATE]);
					write "msg shouldWait value " + aAct.shouldWaitLeaderToActivate;
				}
			}	
		}
	}
	
	action informLeader_round_number {
		map<string,string> msg <- [];
		put NUM_ROUND 		key: OBSERVER_MESSAGE_COMMAND in:msg ;
		put string(game_round) 	key: NUM_ROUND in: msg;
		do send to: GAME_LEADER contents:msg;
	}
				
	action informLeader_indicators_t0  {
		ask District where (each.id > 0) {
			map<string,string> msg <- self.my_indicators_t0;
			put INDICATORS_T0 key: OBSERVER_MESSAGE_COMMAND in: msg;
			put district_code key: DISTRICT_CODE 			in: msg;
			ask myself { do send to: GAME_LEADER contents: msg; }
		}		
	}
	
	reflex informLeader_action_state when: cycle mod 10 = 0 {
		loop act over: Player_Action where (!each.is_sent_to_leader){
			map<string,string> msg <- act.build_map_from_attributes();
			put UPDATE_ACTION_DONE key:OBSERVER_MESSAGE_COMMAND in:msg ;
			do send to:GAME_LEADER contents:msg;
			act.is_sent_to_leader <- true;
			write "send message to leader "+ msg;
		}
	}
}
//------------------------------ End of Network_listener_to_leader -------------------------------//

species Coastal_Defense {	
	int dike_id;
	string district_code;
	string type;     // Dike or Dune
	string status;	//  "Good" "Medium" "Bad"  
	float height;
	float alt; 
	rgb color 			 <- #pink;
	int counter_status	 <- 0;
	int rupture			 <- 0;
	geometry rupture_area<- nil;
	bool not_updated 	 <- false;
	bool ganivelle 		 <- false;
	float height_before_ganivelle;
	list<Cell> cells;
	
	map<string,unknown> build_map_from_attributes{
		map<string,unknown> res <- [
			"OBJECT_TYPE"::"COAST_DEF",	"dike_id"::string(dike_id),	"type"::type, "status"::status,
			"height"::string(height), "alt"::string(alt), "rupture"::string(rupture), "rupture_area"::rupture_area,
			"not_updated"::string(not_updated), "ganivelle"::string(ganivelle), "height_before_ganivelle"::string(height_before_ganivelle),
			"locationx"::string(location.x), "locationy"::string(location.y)];
			int i <- 0;
			loop pp over:shape.points{
				put string(pp.x) key:"locationx"+i in: res;
				put string(pp.y) key:"locationy"+i in: res;
				i <- i+ 1;
			}
		return res;
	}
	
	action init_coastal_def {
		if status = ""  { status <- STATUS_GOOD; 			 } 
		if type = '' 	{ type 	<- "Unknown";				 }
		if height = 0.0 { height <- 1.5;					 } // if no height, 1.5 m by default
		counter_status 	<- type = DUNE ? rnd (STEPS_DEGRAD_STATUS_DUNE - 1) : rnd (STEPS_DEGRAD_STATUS_DIKE - 1);
		cells 			<- Cell overlapping self;
		if type = DUNE  { height_before_ganivelle <- height; }
	}
	
	action build_dike {
		// a new dike raises soil around the highest cell
		float h <- cells max_of (each.soil_height);
		alt 	<- h + height;
		ask cells  {
			soil_height <- h + myself.height;
			soil_height_before_broken <- soil_height ;
			do init_soil_color();
		}
	}
	
	action repaire_dike {
		status <- STATUS_GOOD;
		counter_status <- 0;
	}

	action raise_dike {
		do repaire_dike;
		height 	<- height + RAISE_DIKE_HEIGHT; 
		alt 	<- alt 	  + RAISE_DIKE_HEIGHT;
		ask cells {
			soil_height <- soil_height + RAISE_DIKE_HEIGHT;
			soil_height_before_broken <- soil_height ;
			do init_soil_color();
		}
	}
	
	action destroy_dike {
		ask cells {
			soil_height <- soil_height - myself.height ;
			soil_height_before_broken <- soil_height ;
			do init_soil_color();
		}
		do die;
	}
	
	action degrade_dike_status {
		counter_status <- counter_status + 1;
		if counter_status > STEPS_DEGRAD_STATUS_DIKE {
			counter_status <- 0;
			if status = STATUS_MEDIUM 	{ status <- STATUS_BAD;	  }
			if status = STATUS_GOOD 	{ status <- STATUS_MEDIUM;}
			not_updated <- true; 
		}
	}

	action evolve_dune_status {
		if ganivelle { // a dune with a ganivelle
			counter_status <- counter_status + 1;
			if counter_status > STEPS_REGAIN_STATUS_GANIVELLE {
				counter_status <-0;
				if status = STATUS_MEDIUM 	{ status <- STATUS_GOOD;  }
				if status = STATUS_BAD 		{ status <- STATUS_MEDIUM;}
			}
			if height < height_before_ganivelle + H_MAX_GANIVELLE {
				height 	<- height + H_DELTA_GANIVELLE;  // the dune raises by H_DELTA_GANIVELLE until it reaches H_MAX_GANIVELLE
				alt 	<- alt + H_DELTA_GANIVELLE;
				ask cells {
					soil_height 			  <- soil_height + H_DELTA_GANIVELLE;
					soil_height_before_broken <- soil_height ;
					do init_soil_color();
				}
			} else { ganivelle <- false;	} // if the dune covers all the ganivelle we reset the ganivelle
			not_updated<- true;
		}
		else { // a dune without a ganivelle
			counter_status <- counter_status +1;
			if counter_status > STEPS_DEGRAD_STATUS_DUNE {
				counter_status   <- 0;
				if status = STATUS_MEDIUM { status <- STATUS_BAD;   }
				if status = STATUS_GOOD   { status <- STATUS_MEDIUM;}
				not_updated <- true;  
			}
		}
	}
		
	action calculate_rupture {
		int p <- 0;
		if type = DIKE and status = STATUS_BAD 		{ p <- PROBA_RUPTURE_DIKE_STATUS_BAD;	 }
		if type = DIKE and status = STATUS_MEDIUM  	{ p <- PROBA_RUPTURE_DIKE_STATUS_MEDIUM; }
		if type = DIKE and status = STATUS_GOOD		{ p <- PROBA_RUPTURE_DIKE_STATUS_GOOD;	 }
		if type = DUNE and status = STATUS_BAD 		{ p <- PROBA_RUPTURE_DUNE_STATUS_BAD;	 }
		if type = DUNE and status = STATUS_MEDIUM 	{ p <- PROBA_RUPTURE_DUNE_STATUS_MEDIUM; }
		if type = DUNE and status = STATUS_GOOD 	{ p <- PROBA_RUPTURE_DUNE_STATUS_GOOD;	 }
		if rnd (100) <= p {
			rupture <- 1;
			// the rupture is applied in the middle
			int cIndex <- int(length(cells) / 2);
			// rupture area is about RADIUS_RUPTURE m arount rupture point 
			rupture_area <- circle(RADIUS_RUPTURE#m,(cells[cIndex]).location);
			// rupture is applied on relevant area cells
			ask cells overlapping rupture_area {
				if soil_height >= 0 {	soil_height <- max([0, soil_height - myself.height]);	}
			}
			write "rupture " + type + " n°" + dike_id + "(" + ", status " + status + ", height " + height + ", alt " + alt + ")";
			write "rupture " + type + " n°" + dike_id + "(" + world.table_correspondance_insee_com_nom_rac at (district_code)+ ", status " + status + ", height " + height + ", alt " + alt + ")";
		}
	}
	
	action remove_rupture {
		rupture <- 0;
		ask cells overlapping rupture_area { if soil_height >= 0 { soil_height <- soil_height_before_broken; } }
		rupture_area <- nil;
	}
	
	action install_ganivelle {
		if status = STATUS_BAD {	counter_status <- 2;	}
		else				   {	counter_status <- 0; 	}		
		ganivelle <- true;
		write "" + langs_def at 'MSG_INSTALL_GANIVELLE' at configuration_file["LANGUAGE"];
	}
	
	aspect base {  	
		if type = DUNE {
			switch status {
				match STATUS_GOOD	{	color <-  rgb (222, 134, 14,255);	}
				match STATUS_MEDIUM {	color <-  rgb (231, 189, 24,255);	} 
				match STATUS_BAD 	{	color <-  rgb (241, 230, 14,255);	} 
				default				{	write langs_def at 'MSG_DUNE_STATUS_PROBLEM' at configuration_file["LANGUAGE"];	}
			}
			draw 50#m around shape color: color;
			if ganivelle {	loop i over: points_on (shape, 40#m) { draw circle(10,i) color: #black; } } 
		}else{
			switch status {
				match STATUS_GOOD	{	color <- # green;			}
				match STATUS_MEDIUM {	color <-  rgb (255,102,0);	} 
				match STATUS_BAD 	{	color <- # red;				} 
				default 			{	write langs_def at 'MSG_DIKE_STATUS_PROBLEM' at configuration_file["LANGUAGE"];	}
			}
			draw 20#m around shape color: color size: 300#m;
		}
		if(rupture = 1){
			list<point> pts <- shape.points;
			point tmp <- length(pts) > 2? pts[int(length(pts)/2)] : shape.centroid;
			draw image_file("../images/icones/rupture.png") at: tmp size: 30#px;
		}	
	}
}
//------------------------------ End of Coastal defense -------------------------------//

grid Cell file: dem_file schedules:[] neighbors: 8 {	
	int cell_type 					<- 0 ; // 0 = land
	float water_height  			<- 0.0;
	float max_water_height  		<- 0.0;
	float soil_height 				<- grid_value;
	float soil_height_before_broken <- soil_height;
	float rugosity;
	rgb soil_color ;

	init {
		if soil_height <= 0 {	cell_type 	<- 1;		}  //  1 = sea
		if soil_height = 0 	{	soil_height <- -5.0;	}
		do init_soil_color();
	}
	
	action init_soil_color {
		if cell_type = 1 {
			float tmp  <- ((soil_height  / 10) with_precision 1) * -170;
			soil_color <- rgb( 80, 80 , int(255 - tmp)) ;
		}else{
			float tmp  <- ((soil_height  / 10) with_precision 1) * 255;
			soil_color <- rgb( int(255 - tmp), int(180 - tmp) , 0) ;
		}
	}
	
	aspect water_or_max_water_elevation {
		if cell_type = 1 or (show_max_water_height? (max_water_height = 0) : (water_height = 0)){ // if sea and water level = 0
			color <- soil_color ;
		}else{ // if land
			if show_max_water_height {	color <- world.color_of_water_height(max_water_height);	}
			else					 {	color <- world.color_of_water_height(water_height);		}
		}
	}
}
//------------------------------ End of grid -------------------------------//

species Land_Use {
	int id;
	string lu_name;
	int lu_code;
	rgb my_color 			<- cell_color() update: cell_color();
	int AU_to_U_counter 	<- 0;
	string density_class 	-> {population = 0? POP_EMPTY :(population < POP_FEW_NUMBER ? POP_FEW_DENSITY: (population < POP_MEDIUM_NUMBER ? POP_MEDIUM_DENSITY : POP_DENSE))};
	int exp_cost 			-> {round( population * 400* population ^ (-0.5))};
	bool isUrbanType 		-> {lu_name in ["U","Us","AU","AUs"]};
	bool isAdapted 			-> {lu_name in ["Us","AUs"]};
	bool isInDensification 	<- false;
	bool not_updated 		<- false;
	bool pop_updated 		<- false;
	int population ;
	list<Cell> cells ;
	
	map<string,unknown> build_map_from_attributes {
		map<string,string> res <- [
			"OBJECT_TYPE"::"LU",		"id"::string(id),	"lu_name"::lu_name,
			"lu_code"::string(lu_code),	"STEPS_FOR_AU_TO_U"::string(STEPS_FOR_AU_TO_U),
			"AU_to_U_counter"::string(AU_to_U_counter),	"population"::string(population),
			"isInDensification"::string(isInDensification),	"not_updated"::string(not_updated),
			"pop_updated"::string(pop_updated), "locationx"::string(location.x), "locationy"::string(location.y)];
			int i <- 0;
			loop pp over:shape.points{
				put string(pp.x) key:"locationx"+i in: res;
				put string(pp.y) key:"locationy"+i in: res;
				i<-i+1;
		}
		return res;
	}
		
	action modify_LU (string new_lu_name) {
		if (lu_name in ["U","Us"]) and new_lu_name = "N" { population <-0; } //expropriation
		lu_name <- new_lu_name;
		lu_code <-  lu_type_names index_of lu_name;
		// updating rugosity of related cells
		float rug <- float((eval_gaml("RUGOSITY_"+lu_name)));
		ask cells { rugosity <- rug; } 	
	}
	
	action evolve_AU_to_U {
		if lu_name in ["AU","AUs"]{
			AU_to_U_counter <- AU_to_U_counter + 1;
			if AU_to_U_counter = STEPS_FOR_AU_TO_U {
				AU_to_U_counter <- 0;
				lu_name <- lu_name = "AU" ? "U" : "Us";
				lu_code <- lu_type_names index_of lu_name;
				not_updated <- true;
				do assign_population (POP_FOR_NEW_U);
			}
		}	
	}
	
	action evolve_U_densification {
		if !pop_updated and isInDensification and (lu_name in ["U","Us"]){
			string previous_d_class <- density_class; 
			do assign_population (POP_FOR_U_DENSIFICATION);
			if previous_d_class != density_class { isInDensification <- false; }
		}
	}
		
	action evolve_U_standard { if !pop_updated and (lu_name in ["U","Us"]){	do assign_population (POP_FOR_U_STANDARD);	} }
	
	action assign_population (int nbPop) {
		if new_comers_still_to_dispatch > 0 {
			population 					 <- population + nbPop;
			new_comers_still_to_dispatch <- new_comers_still_to_dispatch - nbPop;
			not_updated 				 <-true;
			pop_updated 				 <- true;
		}
	}

	aspect base {
		draw shape color: my_color;
		if isAdapted		 {	draw "A" color:#black;	}
		if isInDensification {	draw "D" color:#black;	}
	}

	aspect population_density {
		rgb acolor <- nil;
		switch density_class {
			match POP_EMPTY 		{acolor <- # white; }
			match POP_FEW_DENSITY 	{acolor <- listC[2];} 
			match POP_MEDIUM_DENSITY{acolor <- listC[5];}
			match POP_DENSE 		{acolor <- listC[7];}
			default 				{acolor <- # yellow;}
		}
		draw shape color: acolor;
	}
	
	aspect conditional_outline {
		if (Buttons first_with (each.nb_button = 4)).is_selected {	draw shape color: rgb (0,0,0,0) border:#black;	}
	}
	
	rgb cell_color{
		rgb res <- nil;
		switch (lu_name){
			match	  	"N" 				 {res <- #palegreen;			} // natural
			match	  	"A" 				 {res <- rgb (225, 165,0);		} // agricultural
			match_one ["AU","AUs"]  		 {res <- #yellow;		 		} // to urbanize
			match_one ["U","Us"] { 								 	    	  // urbanised
				switch density_class 		 {
					match POP_EMPTY 		 {res <- #red; 					} // Problem ?
					match POP_FEW_DENSITY	 {res <-  rgb( 150, 150, 150 ); }
					match POP_MEDIUM_DENSITY {res <- rgb( 120, 120, 120 ) ; }
					match POP_DENSE 		 {res <- rgb( 80,80,80 ) ;		}
				}
			}			
		}
		return res;
	}
}
//------------------------------ End of Land_Use -------------------------------//

species District{	
	int id <-0;
	string district_code; 
	string district_name;
	string network_name;
	int budget;
	int received_tax <-0;
	list<Land_Use> LUs ;
	list<Cell> cells ;
	float tax_unit  <- float(tax_unit_table at district_name); 
	// init water heights
	float U_0_5c  	  <-0.0;		float U_1c 		<-0.0;		float U_maxc 	  <-0.0;
	float Us_0_5c 	  <-0.0;		float Us_1c 	<-0.0;		float Us_maxc 	  <-0.0;
	float Udense_0_5c <-0.0;		float Udense_1c <-0.0;		float Udense_maxc <-0.0;
	float AU_0_5c 	  <-0.0; 		float AU_1c 	<-0.0;		float AU_maxc 	  <-0.0;
	float A_0_5c 	  <-0.0;		float A_1c 		<-0.0;		float A_maxc      <-0.0;
	float N_0_5c 	  <-0.0;		float N_1c 		<-0.0;		float N_maxc 	  <-0.0;
	
	float flooded_area <- 0.0;	list<float> data_flooded_area<- [];
	float totU 		   <- 0.0;	list<float> data_totU 		 <- [];
	float totUs 	   <- 0.0;	list<float> data_totUs 		 <- [];
	float totUdense	   <- 0.0;	list<float> data_totUdense 	 <- [];
	float totAU 	   <- 0.0;	list<float> data_totAU 		 <- [];
	float totN 		   <- 0.0;	list<float> data_totN 		 <- [];
	float totA 		   <- 0.0;	list<float> data_totA 		 <- [];

	// Indicators calculated at initialization, and sent to Leader when he connects
	map<string,string> my_indicators_t0 <- [];

	aspect base	  {	draw shape color:#whitesmoke;					}
	aspect outline{	draw shape color: rgb (0,0,0,0) border:#black;	}
	
	int current_population {  return sum(LUs accumulate (each.population));	}
	
	action inform_new_round {// inform about a new round (when a district reconnects)
		ask Network_player{
			map<string,string> msg <- ["TOPIC"::"INFORM_NEW_ROUND"];
			put myself.district_code at: DISTRICT_CODE in: msg;
			do send to: myself.district_code + "_map_msg" contents: msg;
		}
	}
	
	action inform_current_round {// inform about the current round (when the player side district reconnects)
		ask Network_player{
			map<string,string> msg <- ["TOPIC"::"INFORM_CURRENT_ROUND"];
			put myself.district_code  		at: DISTRICT_CODE 	in: msg;
			put string(game_round) 		  	at: NUM_ROUND		in: msg;
			do send to: myself.district_code+"_map_msg" contents: msg;
		}
	}

	action inform_budget_update {// inform about the budget (when the player side district reconnects)
		ask Network_player{
			map<string,string> msg <- ["TOPIC"::"DISTRICT_BUDGET_UPDATE"];
			put myself.district_code  	at: DISTRICT_CODE 	in: msg;
			put string(myself.budget) 	at: BUDGET			in: msg;
			do send to: myself.district_code + "_map_msg" contents: msg;
		}
	}
	
	action calculate_taxes {
		received_tax <- int(self.current_population() * tax_unit);
		budget <- budget + received_tax;
		write district_name + "-> tax " + received_tax + " ; budget "+ budget;
	}
	
	action record_payment_for_player_action (Player_Action act){	budget <- int(budget - act.cost);	}
	
	action calculate_indicators_t0 {
		list<Coastal_Defense> my_coast_def <- Coastal_Defense where (each.district_code = district_code);
		put string(my_coast_def where (each.type = DIKE) sum_of (each.shape.perimeter)) key: "length_dikes_t0" in: my_indicators_t0;
		put string(my_coast_def where (each.type = DUNE) sum_of (each.shape.perimeter)) key: "length_dunes_t0" in: my_indicators_t0;
		// built cells (U , AU, Us and AUs)
		put string(length(LUs where (each.isUrbanType))) key: "count_LU_urban_t0" in: my_indicators_t0;
		// non adapted built cells in littoral area (<400m)
		put string(length(LUs where (each.isUrbanType and not(each.isAdapted) and each intersects first(Coastal_Border_Area)))) key: "count_LU_UandAU_inCoastBorderArea_t0" in: my_indicators_t0;
		// built cells in flooded area
		put string(length(LUs where (each.isUrbanType and each intersects all_flood_risk_area))) key: "count_LU_urban_infloodRiskArea_t0" in: my_indicators_t0;
		// dense cells in risk area 
		put string(length(LUs where (each.isUrbanType and each.density_class = POP_DENSE and each intersects all_flood_risk_area))) key: "count_LU_urban_dense_infloodRiskArea_t0" in: my_indicators_t0;
		//dense cells in littoral area
		put string(length(LUs where (each.isUrbanType and each.density_class = POP_DENSE and each intersects union(Coastal_Border_Area)))) key: "count_LU_urban_dense_inCoastBorderArea_t0" in: my_indicators_t0;
		put string(length(LUs where (each.lu_name = 'A'))) 	key: "count_LU_A_t0" 	in: my_indicators_t0; // count cells of type A
		put string(length(LUs where (each.lu_name = 'N'))) 	key: "count_LU_N_t0" 	in: my_indicators_t0; // count cells of type N
		put string(length(LUs where (each.lu_name = 'AU'))) key: "count_LU_AU_t0" 	in: my_indicators_t0; // count cells of type AU
		put string(length(LUs where (each.lu_name = 'U'))) 	key: "count_LU_U_t0" 	in: my_indicators_t0; // count cells of type U
	}				
}
//------------------------------ End of District -------------------------------//
	
// generic buttons
species Buttons{
	int nb_button <- 0;
	string command <- "";
	bool is_selected <- false;
	geometry shape <- square(500#m);
	image_file my_icon;
	
	aspect buttons_master {
		if(nb_button in [0,3,5,6]){
			draw shape   color:  #white border: is_selected ? # red : # white;
			draw my_icon size:	 button_size-50#m ;
		}
	}
	
	aspect buttons_map {
		if( nb_button in [4,7]){
			draw shape   color: #white border: is_selected ? # red : # white;
			draw my_icon size:  800#m ;
		}
	}
}

species Road{				aspect base {	draw shape color: rgb (125,113,53);						}	}

species Protected_Area{		aspect base {	draw shape color: rgb (185, 255, 185,120) border:#black;}	}

species Flood_Risk_Area{	aspect base {	draw shape color: rgb (20, 200, 255,120) border:#black;	}	}
// 400 m littoral area
species Coastal_Border_Area{	aspect base {	draw shape color: rgb (20, 100, 205,120) border:#black;	}	}
//100 m coastline inland area to identify retro dikes
species Inland_Dike_Area{	aspect base {	draw shape color: rgb (100, 100, 205,120) border:#black;}	}

//---------------------------- Experiment definiton -----------------------------//

experiment LittoSIM_GEN type: gui{
	float minimum_cycle_duration <- 0.5;
	parameter "Log User Actions" 	var:log_user_action <- true;
	parameter "Connect to ActiveMQ" var:activemq_connect<- true;
	
	output {
		display "Map"{
			grid Cell;
			species Cell 			aspect: water_or_max_water_elevation;
			species District 		aspect: outline;
			species Road 			aspect: base;
			species Coastal_Defense aspect: base;
			species Land_Use 		aspect: conditional_outline;
			species Buttons 		aspect: buttons_map;
			event [mouse_down] 		action: button_click_map;
		}
		display "Planning"{
			species District 		aspect: base;
			species Land_Use 		aspect: base;
			species Road 	 		aspect: base;
			species Coastal_Defense aspect: base;
		}
		display "Population density"{	
			species Land_Use aspect: population_density;
			species Road 	 aspect: base;
			species District aspect: outline;			
		}
		display "Game master control"{
			species Buttons  aspect: buttons_master;
			event mouse_down action: button_click_master_control;
		}			
		display "Budgets" {
			chart "Districts' budgets" type: series {
			 	data (District first_with(each.id =1)).district_name value:districts_budgets[0] color:#red;
			 	data (District first_with(each.id =2)).district_name value:districts_budgets[1] color:#blue;
			 	data (District first_with(each.id =3)).district_name value:districts_budgets[2] color:#green;
			 	data (District first_with(each.id =4)).district_name value:districts_budgets[3] color:#black;			
			}
		}
		display "Barplots"{
			chart "U Area" type: histogram background: rgb("white") size: {0.31,0.4} position: {0, 0}{
				data "0.5" value:(districts_in_game collect each.U_0_5c) style:stack color: world.color_of_water_height(0.5);
				data  "1"  value:(districts_in_game collect each.U_1c) 	 style:stack color: world.color_of_water_height(0.9); 
				data ">1"  value:(districts_in_game collect each.U_maxc) style:stack color: world.color_of_water_height(1.9); 
			}
			chart "Us Area" type: histogram background: rgb("white") size: {0.31,0.4} position: {0.33, 0}{
				data "0.5" value:(districts_in_game collect each.Us_0_5c) style:stack color: world.color_of_water_height(0.5);
				data  "1"  value:(districts_in_game collect each.Us_1c)   style:stack color: world.color_of_water_height(0.9); 
				data ">1"  value:(districts_in_game collect each.Us_maxc) style:stack color: world.color_of_water_height(1.9); 
			}
			chart "Dense U Area" type: histogram background: rgb("white") size: {0.31,0.4} position: {0.66, 0}{
				data "0.5" value:(districts_in_game collect each.Udense_0_5c) style:stack color: world.color_of_water_height(0.5);
				data  "1"  value:(districts_in_game collect each.Udense_1c)   style:stack color: world.color_of_water_height(0.9); 
				data ">1"  value:(districts_in_game collect each.Udense_maxc) style:stack color: world.color_of_water_height(1.9); 
			}
			chart "AU Area" type: histogram background: rgb("white") size: {0.31,0.4} position: {0, 0.5}{
				data "0.5" value:(districts_in_game collect each.AU_0_5c) style:stack color: world.color_of_water_height(0.5);
				data  "1"  value:(districts_in_game collect each.AU_1c)   style:stack color: world.color_of_water_height(0.9); 
				data ">1"  value:(districts_in_game collect each.AU_maxc) style:stack color: world.color_of_water_height(1.9); 
			}
			chart "A Area" type: histogram background: rgb("white") size: {0.31,0.4} position: {0.33, 0.5}{
				data "0.5" value:(districts_in_game collect each.A_0_5c) style:stack color: world.color_of_water_height(0.5);
				data  "1"  value:(districts_in_game collect each.A_1c)   style:stack color: world.color_of_water_height(0.9); 
				data ">1"  value:(districts_in_game collect each.A_maxc) style:stack color: world.color_of_water_height(1.9); 
			}
			chart "N Area" type: histogram background: rgb("white") size: {0.31,0.4} position: {0.66, 0.5}{
				data "0.5" value:(districts_in_game collect each.N_0_5c) style:stack color: world.color_of_water_height(0.5);
				data  "1"  value:(districts_in_game collect each.N_1c)   style:stack color: world.color_of_water_height(0.9); 
				data ">1"  value:(districts_in_game collect each.N_maxc) style:stack color: world.color_of_water_height(1.9); 
			}
		}
		display "Flooded area per district"{
			chart "Flooded area per district" type: series{
				datalist value: length(District)= 0 ? [0,0,0,0]:[((District first_with(each.id = 1)).data_flooded_area),
																 ((District first_with(each.id = 2)).data_flooded_area),
																 ((District first_with(each.id = 3)).data_flooded_area),
																 ((District first_with(each.id = 4)).data_flooded_area)]
						color:[#red,#blue,#green,#black] legend: (((District where (each.id > 0)) sort_by (each.id)) collect each.district_name); 			
			}
		}
		display "Flooded U area per district"{
			chart "Flooded U area per district" type: series{
				datalist value:length(District) = 0 ? [0,0,0,0]:[((District first_with(each.id = 1)).data_totU),
																 ((District first_with(each.id = 2)).data_totU),
																 ((District first_with(each.id = 3)).data_totU),
																 ((District first_with(each.id = 4)).data_totU)]
						color:[#red,#blue,#green,#black] legend: (((District where (each.id > 0)) sort_by (each.id)) collect each.district_name); 			
			}
		}
		display "Flooded Us area per district"{
			chart "Flooded Us area per district" type: series{
				datalist value:length(District) = 0 ? [0,0,0,0]:[((District first_with(each.id = 1)).data_totUs),
																 ((District first_with(each.id = 2)).data_totUs),
																 ((District first_with(each.id = 3)).data_totUs),
																 ((District first_with(each.id = 4)).data_totUs)]
						color:[#red,#blue,#green,#black] legend: (((District where (each.id > 0)) sort_by (each.id)) collect each.district_name); 			
			}
		}
		display "Flooded dense U area per district"{
			chart "Flooded dense U area per district" type: series{
				datalist value:length(District) = 0 ? [0,0,0,0]:[((District first_with(each.id = 1)).data_totUdense),
																 ((District first_with(each.id = 2)).data_totUdense),
																 ((District first_with(each.id = 3)).data_totUdense),
																 ((District first_with(each.id = 4)).data_totUdense)]
						color:[#red,#blue,#green,#black] legend: (((District where (each.id > 0)) sort_by (each.id)) collect each.district_name); 			
			}
		}
		display "Flooded AU area per district"{
			chart "Flooded AU area per district" type: series{
				datalist value:length(District) = 0 ? [0,0,0,0]:[((District first_with(each.id = 1)).data_totAU),
																 ((District first_with(each.id = 2)).data_totAU),
																 ((District first_with(each.id = 3)).data_totAU),
																 ((District first_with(each.id = 4)).data_totAU)]
						color:[#red,#blue,#green,#black] legend: (((District where (each.id > 0)) sort_by (each.id)) collect each.district_name); 			
			}
		}
		display "Flooded N area per district"{
			chart "Flooded N area per district" type: series{
				datalist value:length(District) = 0 ? [0,0,0,0]:[((District first_with(each.id = 1)).data_totN),
																 ((District first_with(each.id = 2)).data_totN),
																 ((District first_with(each.id = 3)).data_totN),
																 ((District first_with(each.id = 4)).data_totN)]
						color:[#red,#blue,#green,#black] legend: (((District where (each.id > 0)) sort_by (each.id)) collect each.district_name); 			
			}
		}
		display "Flooded A area per district"{
			chart "Flooded A area per district" type: series{
				datalist value:length(District) = 0 ? [0,0,0,0]:[((District first_with(each.id = 1)).data_totA),
																 ((District first_with(each.id = 2)).data_totA),
																 ((District first_with(each.id = 3)).data_totA),
																 ((District first_with(each.id = 4)).data_totA)]
						color:[#red,#blue,#green,#black] legend: (((District where (each.id > 0)) sort_by (each.id)) collect each.district_name); 			
			}
		}
	}
}
		