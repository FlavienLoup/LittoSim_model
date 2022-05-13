/***
* Name: Actions
* Author: flavi
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model Actions

global{
	//DEBUG DATA
	int action_heavl;
	int action_hardl;
	int action_ml;
	int action_sl;
	int action_hb;
	
	
	list<bot_action> action_list ;
	init{
		
		
		action_heavl <- 0 ;
		action_hardl <- 0;
		action_ml <- 0;
		action_sl <- 0;
		action_hb <- 0;
		
		
		create heavy_litoral_security returns: action0;
		create hard_litoral_security returns: action1;
		create medium_litoral_security returns: action2;
		create soft_litoral_security returns: action3;
		create hard_land_budget returns: action4;
		
		action_list <- [action0[0],action1[0],action2[0],action3[0],action4[0]];
	
	}
}



species bot_action{
	int pointer;
	float base_proba ;

	action set_pointer(int i){
		self.pointer <- i;
		//base_proba <- bot.actions_probas[pointer];
	}
	//action execute{ do function;}
	action function{ } //rename behaviour
}

species heavy_litoral_security parent:bot_action{ //action used when the emmergency of flood is the highest
	init {}
	action function {
		/*TODO*/
		//add function create a dike
		write self;
		action_heavl <- action_heavl+1 ;
		

	}
}
species hard_litoral_security parent:bot_action{ //actions used when the emmergency of flood is high	
	init {}
	action function {
		/*TODO*/
		//add functions raise_dike, create_dune & change_to_us
		action_hardl <- action_hardl+1;
		
	}
}
species medium_litoral_security parent:bot_action{ //actions used when the player think he is quite safe
	init {}
	action function {
		/*TODO*/
		//add functions load_pebbles repair_dike & install_send_fences
		action_ml <- action_ml+1;
		
	}
}
species soft_litoral_security parent:bot_action{ //actions used when the player think he is safe 
	init {}
	action function {
		/*TODO*/
		//add maintain_dune
		action_sl <- action_sl+1;
	}
}

species hard_land_budget parent:bot_action{ //action used when the budget is low and ther is no big emergency of flooding
	init {}
	action function {
		/*TODO*/
		//
		action_hb <- action_hb+1;
	}
}

experiment test{}
/* Insert your model definition here */

