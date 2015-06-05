#$@ is the file name of the target of the rule. 
#example get from s3:aws s3 cp s3://landuse/zoning/match_fields_tables_zoning_2012_source.csv match_fields_tables_zoning_2012_source.csv
get = aws s3 cp s3://landuse/zoning/
DBUSERNAME=vagrant
DBPASSWORD=vagrant
DBHOST=localhost
DBPORT=5432
DBNAME=mtc 
psql = PGPASSWORD=vagrant psql -p $(DBPORT) -h $(DBHOST) -U $(DBUSERNAME) $(DBNAME)
shp2pgsql = shp2pgsql -t 2D -s 26910 -I


#########################
##Join Parcels/Zoning####
#########################

parcel_zoning.csv:
	mkdir -p data_out
	$(psql) -f process/merge_jurisdiction_zoning.sql
	$(psql) -f process/parcel_zoning_intersection.sql

add_plu06:
	$(psql) \
	-f load/add-plu-2006.sql

assign_zoning_to_parcels:
	$(psql) -f process/prepare_parcels.sql
	$(psql) -f process/prepare_zoning.sql
	$(psql) -f process/assign_admin_to_parcels.sql
	$(psql) -f process/create_intersection_table.sql
	$(psql) -f process/get_stats_on_intersection.sql
	$(psql) -f process/create_zoning_parcel_overlaps_table.sql

	$(psql) -f process/fill_in_zoning_parcel_table.sql
	$(psql) -f process/check_zoning_parcel_table.sql

	$(psql) -f process/stats_on_overlaps.sql

#########################
####LOAD IN POSTGRES#####
#########################

load_zoning_data: load_zoning_by_jurisdiction \
	fix_errors_in_source_zoning \
	load_admin_boundaries \
	add_plu06 \
	load_zoning_codes

load_admin_boundaries:
	$(psql) -c "CREATE SCHEMA admin"
	shp2pgsql city10_ba.shp admin.city10_ba | $(psql)
	#for city10_ba had to delete columns: sqmi, aland, awater b/c stored as numeric(17,17) 
	#which was beyond capabilities of shapefile, latter 2 replaced with INT, former easy to make w/PostGIS
	#old file saved here: http://landuse.s3.amazonaws.com/zoning/city10_ba_original.zip
	shp2pgsql county10_ca.shp admin.county10_ca | $(psql)

load_zoning_by_jurisdiction:
	$(psql) -c "CREATE SCHEMA zoning_staging"
	#JURISDICTION-BASED ZONING SOURCE DATA
	ls jurisdictional/*.shp | cut -d "/" -f2 | sed 's/.shp//' | \
	xargs -I {} $(shp2pgsql) jurisdictional/{} zoning_staging.{} | \
	$(psql)

load_zoning_codes:
	$(psql) -f load/load-generic-zoning-code-table.sql

fix_errors_in_source_zoning:
	#FIX for Napa
	#Can't SELECT with shp2pgsql--trying this:
	$(psql) -c "CREATE TABLE zoning_staging.napacozoning_temp AS SELECT zoning, geom from zoning_staging.napacozoning;"
	$(psql) -c "DROP TABLE zoning_staging.napacozoning;"
	$(psql) -c "CREATE TABLE zoning_staging.napacozoning AS SELECT * from zoning_staging.napacozoning_temp;"
	$(psql) -c "DROP TABLE zoning_staging.napacozoning_temp;"

	#FIX for Solano
	$(psql) -c "CREATE TABLE zoning_staging.solcogeneral_plan_unincorporated_temp AS SELECT full_name, geom from zoning_staging.solcogeneral_plan_unincorporated;"
	$(psql) -c "DROP TABLE zoning_staging.solcogeneral_plan_unincorporated;"
	$(psql) -c "CREATE TABLE zoning_staging.solcogeneral_plan_unincorporated AS SELECT * from zoning_staging.solcogeneral_plan_unincorporated_temp;"
	$(psql) -c "DROP TABLE zoning_staging.solcogeneral_plan_unincorporated_temp;"

load_plu06:
	$(shp2pgsql) plu06_may2015estimate.shp zoning.plu06_may2015estimate | $(psql)

##############
###PREPARE####
##############

City_Santa_Clara_GP_LU_02.shp: City_Santa_Clara_GP_LU_02.zip
	unzip -o $<
	touch $@

jurisdictional/AlamedaCountyGP2006db.shp: PlannedLandUsePhase1.gdb
	bash load/jurisdiction_shapefile_directory.sh
	touch jurisdictional/*

PlannedLandUsePhase1.gdb: PlannedLandUse1Through6.gdb.zip
	unzip -o $<
	touch $@

county10_ca.shp: county10_ca.zip
	unzip -o $<
	touch $@

city10_ba.shp: city10_ba.zip
	unzip -o $<
	touch $@

PLU2008_Updated.shp: PLU2008_Updated.zip
	unzip -o $<
	touch $@

no_dev_array.csv: no_dev1.txt
	cp no_dev1.txt no_dev1.csv
	ogr2ogr -f csv -overwrite -select GEOM_ID no_dev_array.csv no_dev1.csv


##############
###DOWNLOAD###
##############

City_Santa_Clara_GP_LU_02.zip: 
	$(get)$@ \
	$@.download
	mv $@.download $@

#where plu refers to the old "planned land use"/comprehensive plan project
ba8parcels.sql:
	$(get)ba8parcels.sql \
	$@.download
	mv $@.download $@

parcels_spandex.sql:
	$(get)parcels_spandex.sql \
	$@.download
	mv $@.download $@

zoning_codes_base2012.csv:
	$(get)zoning_codes_base2012.csv \
	$@.download
	mv $@.download $@

city10_ba.zip:
	$(get)city10_ba.zip \
	$@.download
	mv $@.download $@

zoning_codes_base2008.csv:
	$(get)zoning_codes_base2008.csv \
	-o zoning_codes_base2008.csv

county10_ca.zip:
	$(get)county10_ca.zip \
	$@.download
	mv $@.download $@

match_fields_tables_zoning_2012_source.csv:
	$(get)match_fields_tables_zoning_2012_source.csv \
	$@.download
	mv $@.download $@

PlannedLandUse1Through6.gdb.zip:
	$(get)PlannedLandUse1Through6.gdb.zip \
	$@.download
	mv $@.download $@

PLU2008_Updated.zip:
	$(get)PLU2008_Updated.zip \
	$@.download
	mv $@.download $@

plu06_may2015estimate.zip:
	$(get)plu06_may2015estimate.zip \
	$@.download
	mv $@.download $@

no_dev1.txt:
	$(get)$@ \
	$@.download
	mv $@.download $@
	touch $@

###################
##General Targets##
###################

clean_zoning_data: 
	$(psql) -c "DROP SCHEMA zoning CASCADE;"
	$(psql) -c "DROP SCHEMA zoning_staging CASCADE;"

clean_db:
	sudo bash load/clean_db.sh
	
clean_intersection_tables:
	$(psql)	-f load/drop_intersection_tables.sql

merge_source_zoning:
	$(psql) -f process/merge_jurisdiction_zoning.sql

zoning_parcel_intersection:
	$(psql) \
	-f process/parcel_zoning_intersection.sql

clean_shapefiles:
	rm -rf jurisdictional

sql_dump:
	pg_dump --table zoning.parcel_withdetails \
	-f /mnt/bootstrap/zoning/data_out/zoning_parcel_withdetails.sql \
	vagrant
	pg_dump --table zoning.parcel_withdetails \
	-f /mnt/bootstrap/zoning/data_out/zoning_parcel.sql \
	vagrant

remove_source_data:
	rm ba8parcels.* 
	rm city10_ba.* 
	rm county10_ca.* 
	rm match_fields_tables_zoning_2012_source.* 
	rm parcels_spandex.* 
	rm Parcels2010_Update9.* 
	rm jurisdictional/*.* 
	rm zoning_codes_base2012.* 
	rm PLU2008_Updated.*
	rm PlannedLandUsePhase*
