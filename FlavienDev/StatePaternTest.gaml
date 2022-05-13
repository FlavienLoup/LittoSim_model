/***
* Name: StatePaternTest
* Author: flavi
* Description: 
* Tags: Tag1, Tag2, TagN
***/



model StatePaternTest

import "../LittoSIM-GEN_Player.gaml"

import "Etat.gaml"

import "Actions.gaml"


global {
	
	int budget_seuil;
	/*DEBUG DATA*/
	int nb_action_ <-0;
	
	
	//int nb_state <-3;		//nombre d'etat que peux prendre la simulation (nombre d'action possible pour le moment)
	//list<list<float>> matrice <- nb_state list_with (nb_state list_with 0);
	
	init{		
		create bot_contexte;//create the contexte of the simulation
		
		try{
			//create Network_bot;
		}
		catch{
			write "unable to create Network_bot";
		}
	}
	
}

species Network_bot skills:[network]{
	init {do connect to: SERVER with_name:"Bot_communication";}


}


species bot_contexte {		//species that represent the curent context of the simulation it will allow to have information such as the current turn, the level of flood if needed
	state_ current_state;
	state_ estimated_state;
	//District d;
	init{
		//d <- active_district;
		create state0 returns:etat0;
		current_state <- etat0[0];
		estimated_state <- current_state;
		ask etat0 {do faitUnTruc();}
		ask current_state {do faitUnTruc();}
		//write my_state.text;
	}
	/*action change_etat{
		current_state <- current_state.change();
	}*/
	
	action calculate_state{ //calcule the current state at the begining of each turn
		int urgence;
		
		
		//TODO calculate urgence:
		urgence <- rnd(0,4);
		
		switch (urgence){
			match 0 {if budget > budget_seuil {self.current_state <- listeEtat[0];} else {self.current_state <- listeEtat[1];}}
			match 1 {if budget > budget_seuil {self.current_state <- listeEtat[2];} else {self.current_state <- listeEtat[3];}}
//			match 2 {if budget > budget_seuil {self.current_state <- listeEtat[4];} else {self.current_state <- listeEtat[5];}}
//			match 3 {if budget > budget_seuil {self.current_state <- listeEtat[6];} else {self.current_state <- listeEtat[7];}}
//			match 4 {if budget > budget_seuil {self.current_state <- listeEtat[8];} else {self.current_state <- listeEtat[9];}}
		}
	}
	
	action etimate_next_state (int num_action){ //estimate the the state after each action
		/*estimate urgence :
		 * 					0, only N inondé
		 * 					1, pas de U inondé mais des A
		 * 					2, U innondé - d'1m
		 * 					3, U inondé + d'1m
		 *                  4, Udense innondé et/ou beaucoup de U + d'1m */
		 
		int estimate_budget;
		int estimate_urgence;
		
		estimate_urgence <- rnd(0,4);
		estimate_budget<- rnd(-5,5);
		
		//TODO estimate budget and urgence depending on the action performed
		
		/*switch(num_action){
			match 0{estimate_budget <- 0; estimate_urgence <- 0;}
		}*/
		
		switch (estimate_urgence){
			match 0 {if estimate_budget >= 0 {self.current_state <- listeEtat[0];} else {self.current_state <- listeEtat[1];}}
			match 1 {if estimate_budget >= 0 {self.current_state <- listeEtat[2];} else {self.current_state <- listeEtat[3];}}
//			match 2 {if estimate_budget > 0 {self.current_state <- listeEtat[4];} else {self.current_state <- listeEtat[5];}}
//			match 3 {if estimate_budget > 0 {self.current_state <- listeEtat[6];} else {self.current_state <- listeEtat[7];}}
//			match 4 {if estimate_budget > 0 {self.current_state <- listeEtat[8];} else {self.current_state <- listeEtat[9];}}
		}
		
		
	}
	
	reflex behaviour{
		int i;
		int n <- 0;
		
		do calculate_state;
		estimated_state <- current_state;
		
		loop while: n<5{
			nb_action_ <- nb_action_+1;
			ask estimated_state{do faitUnTruc;}
			i <- estimated_state.select_action();
			ask action_list[i]{ do function;}
			do etimate_next_state(i);
			n<-n+1;
		}
		
		
		
	}
}




experiment _Player_BOT_  parent: LittoSIM_GEN_Player {
	init{}
	output{
		display action_ratio{
				chart "action ration" type: histogram{	
					data "nb_action_"	value: nb_action_;	
					data "action_heavl" value: action_heavl;
					data "action_hardl" value: action_hardl;
					data "action_ml" value: action_ml;
					data "action_sl" value: action_sl;
					data "action_hb" value: action_hb;
					
				}
				
			}
		
		display etat_ratio{
				chart "etat ration" type: histogram{	
					data "nb_action_"	value: nb_action_;	
					data "etat 1" value: etat_1;
					data "etat 2" value: etat_2;
					data "etat 3" value: etat_3;
					data "etat 4" value: etat_4;
					
				}
				
			}
		}
}
