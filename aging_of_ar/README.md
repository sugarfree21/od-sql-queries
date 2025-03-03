# What is in this folder?

This folder contains all of my notes dissecting Open Dental's default Aging of A/R report (Reports > Standard > Monthly > Aging of A/R).  

I've also heavily commented this code, but in a way that may not be helpful for others to work with. I'll clean it up if I have time. 

Here are the settings that I used to generate the query:  
![report_settings](aging_of_ar.png)

## Explanation of Files

`aging_of_ar.sql` - This is the unedited sql query used to generate the report. 

Because the query contains no less than 6 combined tables and 6 nested SELECT statements, I created a new sql file for each new layer of the "nesting doll" so that I could see what each new SELECT statement was modifying. 