/***
* Name: Etat
* Author: flavi
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model Etat

global{
	
	int nb_state <- 4;
	int nb_action <- 5;
	
	int etat_1;
	int etat_2;
	int etat_3;
	int etat_4;
	
	
	list<state_> listeEtat;
	list<list<float>> matrice <- nb_state list_with (nb_action list_with 0);
	
	
	init{
		
		/*temporary variable declaration */
		csv_file Matrice_test <- csv_file("Matrice_test.csv",";",true); //read the source files
		list<string> list_of_string <- list(Matrice_test); 				//list of strings in the file
		list<list> tmp;													//tempopary list of list used to split strings
		/*********************************/
		
		/*Fill variable to avoid null pointer exception */
		tmp <- nb_state list_with [];
		//matrice 
		/************************************************/
		
		/*Converting CSV_file into lists of string */
		int i <-0;
		loop line over:list_of_string{
			tmp[i] <- line split_with ",";							//split the list of string with ,
			i <- i+1;
		}
		/*******************************************/
		
		/*Converting lists of string into list of float */
		loop i from:0 to:length(tmp)-1{					//from 0 to nb of state possible
			loop j from:1 to:length(tmp[i])-1{			//from 1 to nb of state possible+1 (+1 to avoid the name of the state)
				matrice[i][j-1]<-float(tmp[i][j]);
			}	
		}
		//write matrice;
	
		create highUrgenceAndGoodIncome returns:etat1;
		create highUrgenceAndLowIncome returns:etat2;
		create urgenceAndGoodIncome returns:etat3;
		create urgenceAndLowIncome returns:etat4;
		listeEtat <- [etat1[0],etat2[0],etat3[0],etat4[0]];
		
		ask listeEtat[0] {do select_action();}
		}
}


species state_{
	list<float> probas;
	int rank;
	
	init {
		do create_proba;
	}
	action faitUnTruc{
		write "coucou";
	}
	
	action create_proba{
		list<float> liste_proba;
		//write ""+self+"matrice_proba :"+matrice[0][0];
		
		
	}
	
	int select_action{
		int ret;
		float dice <- rnd(0.0,1.0);
		write dice;
		
		float sum <-0.0;
		loop i from:0 to:length(probas)-1{
			sum <- sum+probas[i];
			write "sum = " + sum;
			if (sum>=dice){
				write i;
				return  i;
			}
		}
	}
}

species state0 parent:state_{ // Etat initiale de la simulation
	action faitUnTruc{	//override etat.faitUnTruc
		
	}
	init{
		rank <- 0;
		probas <- matrice[rank];
		
	}
}

species highUrgenceAndGoodIncome parent:state_{
	action faitUnTruc{
		etat_1 <- etat_1+1;
		/*TODO*/
		//add function create a dike
		
		
		//action1 <- action1+1;
		//nb_action <- nb_action+1;
	}
	
	init{
		rank <- 0;
		probas <- matrice[rank];
		
	}
}

species highUrgenceAndLowIncome parent:state_{
	action faitUnTruc{
		etat_2 <- etat_2+1;
		/*TODO*/
		//add functions raise_dike, create_dune & change_to_us
		
		
		//action2 <- action2+1;
		//nb_action <- nb_action+1;
	}
	init{
		rank <- 1;
		probas <- matrice[rank];
		
	}
}

species urgenceAndGoodIncome parent:state_{
	action faitUnTruc{
		etat_3 <- etat_3+1;
		/*TODO*/
		//add functions load_pebbles repair_dike & install_send_fences
		
		
		//action3 <- action3+1;
		//nb_action <- nb_action+1;
	}
	init{
		rank <- 2;
		probas <- matrice[rank];
		
	}
}

species urgenceAndLowIncome parent:state_{
	action faitUnTruc{
		etat_4 <- etat_4+1;
		/*TODO*/
		//add maintain_dune
		
		
		/*action3 <- action3+1;
		nb_action <- nb_action+1;*/
	}
	init{
		rank <- 3;
		probas <- matrice[rank];
		
	}
}

species lowBudget parent:state_{
	action faitUnTruc{
		/*TODO*/
		
	}
	init{
		rank <- 4;
		probas <- matrice[rank];
		
	}
}
experiment test{}
/* Insert your model definition here */

