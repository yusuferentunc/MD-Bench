/*
 * Copyright (C) 2022 NHR@FAU, University Erlangen-Nuremberg.
 * All rights reserved. This file is part of MD-Bench.
 * Use of this source code is governed by a LGPL-3.0
 * license that can be found in the LICENSE file.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include <atom.h>
#include <allocate.h>
#include <device.h>
#include <util.h>

#define DELTA 20000

#ifndef MAXLINE
#define MAXLINE 4096
#endif

#ifndef MAX
#define MAX(a,b)    ((a) > (b) ? (a) : (b))
#endif

void initAtom(Atom *atom) {
    atom->x  = NULL; atom->y  = NULL; atom->z  = NULL;
    atom->vx = NULL; atom->vy = NULL; atom->vz = NULL;
    atom->fx = NULL; atom->fy = NULL; atom->fz = NULL;
    atom->Natoms = 0;
    atom->Nlocal = 0;
    atom->Nghost = 0;
    atom->Nmax   = 0;
    atom->type = NULL;
    atom->ntypes = 0;
    atom->epsilon = NULL;
    atom->sigma6 = NULL;
    atom->cutforcesq = NULL;
    atom->cutneighsq = NULL;
    atom->radius = NULL;
    atom->av = NULL;
    atom->r = NULL;

    DeviceAtom *d_atom = &(atom->d_atom);
    d_atom->x  = NULL; d_atom->y  = NULL; d_atom->z  = NULL;
    d_atom->vx = NULL; d_atom->vy = NULL; d_atom->vz = NULL;
    d_atom->fx = NULL; d_atom->fy = NULL; d_atom->fz = NULL;
    d_atom->border_map = NULL;
    d_atom->type = NULL;
    d_atom->epsilon = NULL;
    d_atom->sigma6 = NULL;
    d_atom->cutforcesq = NULL;
    d_atom->cutneighsq = NULL;
}

void createAtom(Atom *atom, Parameter *param) {
    MD_FLOAT xlo = 0.0; MD_FLOAT xhi = param->xprd;
    MD_FLOAT ylo = 0.0; MD_FLOAT yhi = param->yprd;
    MD_FLOAT zlo = 0.0; MD_FLOAT zhi = param->zprd;
    atom->Natoms = 4 * param->nx * param->ny * param->nz;
    atom->Nlocal = 0;
    atom->ntypes = param->ntypes;
    atom->epsilon = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->sigma6 = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->cutforcesq = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->cutneighsq = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    for(int i = 0; i < atom->ntypes * atom->ntypes; i++) {
        atom->epsilon[i] = param->epsilon;
        atom->sigma6[i] = param->sigma6;
        atom->cutneighsq[i] = param->cutneigh * param->cutneigh;
        atom->cutforcesq[i] = param->cutforce * param->cutforce;
    }

    MD_FLOAT alat = pow((4.0 / param->rho), (1.0 / 3.0));
    int ilo = (int) (xlo / (0.5 * alat) - 1);
    int ihi = (int) (xhi / (0.5 * alat) + 1);
    int jlo = (int) (ylo / (0.5 * alat) - 1);
    int jhi = (int) (yhi / (0.5 * alat) + 1);
    int klo = (int) (zlo / (0.5 * alat) - 1);
    int khi = (int) (zhi / (0.5 * alat) + 1);

    ilo = MAX(ilo, 0);
    ihi = MIN(ihi, 2 * param->nx - 1);
    jlo = MAX(jlo, 0);
    jhi = MIN(jhi, 2 * param->ny - 1);
    klo = MAX(klo, 0);
    khi = MIN(khi, 2 * param->nz - 1);

    MD_FLOAT xtmp, ytmp, ztmp, vxtmp, vytmp, vztmp;
    int i, j, k, m, n;
    int sx = 0; int sy = 0; int sz = 0;
    int ox = 0; int oy = 0; int oz = 0;
    int subboxdim = 8;

    while(oz * subboxdim <= khi) {

        k = oz * subboxdim + sz;
        j = oy * subboxdim + sy;
        i = ox * subboxdim + sx;

        if(((i + j + k) % 2 == 0) &&
                (i >= ilo) && (i <= ihi) &&
                (j >= jlo) && (j <= jhi) &&
                (k >= klo) && (k <= khi)) {

            xtmp = 0.5 * alat * i;
            ytmp = 0.5 * alat * j;
            ztmp = 0.5 * alat * k;

            if( xtmp >= xlo && xtmp < xhi &&
                    ytmp >= ylo && ytmp < yhi &&
                    ztmp >= zlo && ztmp < zhi ) {

                n = k * (2 * param->ny) * (2 * param->nx) +
                    j * (2 * param->nx) +
                    i + 1;

                for(m = 0; m < 5; m++) {
                    myrandom(&n);
                }
                vxtmp = myrandom(&n);

                for(m = 0; m < 5; m++){
                    myrandom(&n);
                }
                vytmp = myrandom(&n);

                for(m = 0; m < 5; m++) {
                    myrandom(&n);
                }
                vztmp = myrandom(&n);

                if(atom->Nlocal == atom->Nmax) {
                    growAtom(atom);
                }

                atom_x(atom->Nlocal) = xtmp;
                atom_y(atom->Nlocal) = ytmp;
                atom_z(atom->Nlocal) = ztmp;
                atom_vx(atom->Nlocal) = vxtmp;
                atom_vy(atom->Nlocal) = vytmp;
                atom_vz(atom->Nlocal) = vztmp;
                atom->type[atom->Nlocal] = rand() % atom->ntypes;
                atom->Nlocal++;
            }
        }

        sx++;

        if(sx == subboxdim) { sx = 0; sy++; }
        if(sy == subboxdim) { sy = 0; sz++; }
        if(sz == subboxdim) { sz = 0; ox++; }
        if(ox * subboxdim > ihi) { ox = 0; oy++; }
        if(oy * subboxdim > jhi) { oy = 0; oz++; }
    }
}

int type_str2int(const char *type) {
    if(strncmp(type, "Ar", 2) == 0) { return 0; } // Argon
    fprintf(stderr, "Invalid atom type: %s\n", type);
    exit(-1);
    return -1;
}

int readAtom(Atom* atom, Parameter* param) {
    int len = strlen(param->input_file);
    if(strncmp(&param->input_file[len - 4], ".pdb", 4) == 0) { return readAtom_pdb(atom, param); }
    if(strncmp(&param->input_file[len - 4], ".gro", 4) == 0) { return readAtom_gro(atom, param); }
    if(strncmp(&param->input_file[len - 4], ".dmp", 4) == 0) { return readAtom_dmp(atom, param); }
    if(strncmp(&param->input_file[len - 3], ".in",  3) == 0) { return readAtom_in(atom, param); }
    fprintf(stderr, "Invalid input file extension: %s\nValid choices are: pdb, gro, dmp, in\n", param->input_file);
    exit(-1);
    return -1;
}

int readAtom_pdb(Atom* atom, Parameter* param) {
    FILE *fp = fopen(param->input_file, "r");
    char line[MAXLINE];
    int read_atoms = 0;

    if(!fp) {
        fprintf(stderr, "Could not open input file: %s\n", param->input_file);
        exit(-1);
        return -1;
    }

    while(!feof(fp)) {
        readline(line, fp);
        char *item = strtok(line, " ");
        if(strncmp(item, "CRYST1", 6) == 0) {
            param->xlo = 0.0;
            param->xhi = atof(strtok(NULL, " "));
            param->ylo = 0.0;
            param->yhi = atof(strtok(NULL, " "));
            param->zlo = 0.0;
            param->zhi = atof(strtok(NULL, " "));
            param->xprd = param->xhi - param->xlo;
            param->yprd = param->yhi - param->ylo;
            param->zprd = param->zhi - param->zlo;
            // alpha, beta, gamma, sGroup, z
        } else if(strncmp(item, "ATOM", 4) == 0) {
            char *label;
            int atom_id, comp_id;
            MD_FLOAT occupancy, charge;
            atom_id = atoi(strtok(NULL, " ")) - 1;

            while(atom_id + 1 >= atom->Nmax) {
                growAtom(atom);
            }

            atom->type[atom_id] = type_str2int(strtok(NULL, " "));
            label = strtok(NULL, " ");
            comp_id = atoi(strtok(NULL, " "));
            atom_x(atom_id) = atof(strtok(NULL, " "));
            atom_y(atom_id) = atof(strtok(NULL, " "));
            atom_z(atom_id) = atof(strtok(NULL, " "));
            atom_vx(atom_id) = 0.0;
            atom_vy(atom_id) = 0.0;
            atom_vz(atom_id) = 0.0;
            occupancy = atof(strtok(NULL, " "));
            charge = atof(strtok(NULL, " "));
            atom->ntypes = MAX(atom->type[atom_id] + 1, atom->ntypes);
            atom->Natoms++;
            atom->Nlocal++;
            read_atoms++;
        } else if(strncmp(item, "HEADER", 6) == 0 ||
                  strncmp(item, "REMARK", 6) == 0 ||
                  strncmp(item, "MODEL", 5) == 0 ||
                  strncmp(item, "TER", 3) == 0 ||
                  strncmp(item, "ENDMDL", 6) == 0) {
            // Do nothing
        } else {
            fprintf(stderr, "Invalid item: %s\n", item);
            exit(-1);
            return -1;
        }
    }

    if(!read_atoms) {
        fprintf(stderr, "Input error: No atoms read!\n");
        exit(-1);
        return -1;
    }

    atom->epsilon = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->sigma6 = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->cutforcesq = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->cutneighsq = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    for(int i = 0; i < atom->ntypes * atom->ntypes; i++) {
        atom->epsilon[i] = param->epsilon;
        atom->sigma6[i] = param->sigma6;
        atom->cutneighsq[i] = param->cutneigh * param->cutneigh;
        atom->cutforcesq[i] = param->cutforce * param->cutforce;
    }

    fprintf(stdout, "Read %d atoms from %s\n", read_atoms, param->input_file);
    fclose(fp);
    return read_atoms;
}

int readAtom_gro(Atom* atom, Parameter* param) {
    FILE *fp = fopen(param->input_file, "r");
    char line[MAXLINE];
    char desc[MAXLINE];
    int read_atoms = 0;
    int atoms_to_read = 0;
    int i = 0;

    if(!fp) {
        fprintf(stderr, "Could not open input file: %s\n", param->input_file);
        exit(-1);
        return -1;
    }

    readline(desc, fp);
    for(i = 0; desc[i] != '\n'; i++);
    desc[i] = '\0';
    readline(line, fp);
    atoms_to_read = atoi(strtok(line, " "));
    fprintf(stdout, "System: %s with %d atoms\n", desc, atoms_to_read);

    while(!feof(fp) && read_atoms < atoms_to_read) {
        readline(line, fp);
        char *label = strtok(line, " ");
        int type = type_str2int(strtok(NULL, " "));
        int atom_id = atoi(strtok(NULL, " ")) - 1;
        atom_id = read_atoms;
        while(atom_id + 1 >= atom->Nmax) {
            growAtom(atom);
        }

        atom->type[atom_id] = type;
        atom_x(atom_id) = atof(strtok(NULL, " "));
        atom_y(atom_id) = atof(strtok(NULL, " "));
        atom_z(atom_id) = atof(strtok(NULL, " "));
        atom_vx(atom_id) = atof(strtok(NULL, " "));
        atom_vy(atom_id) = atof(strtok(NULL, " "));
        atom_vz(atom_id) = atof(strtok(NULL, " "));
        atom->ntypes = MAX(atom->type[atom_id] + 1, atom->ntypes);
        atom->Natoms++;
        atom->Nlocal++;
        read_atoms++;
    }

    if(!feof(fp)) {
        readline(line, fp);
        param->xlo = 0.0;
        param->xhi = atof(strtok(line, " "));
        param->ylo = 0.0;
        param->yhi = atof(strtok(NULL, " "));
        param->zlo = 0.0;
        param->zhi = atof(strtok(NULL, " "));
        param->xprd = param->xhi - param->xlo;
        param->yprd = param->yhi - param->ylo;
        param->zprd = param->zhi - param->zlo;
    }

    if(read_atoms != atoms_to_read) {
        fprintf(stderr, "Input error: Number of atoms read do not match (%d/%d).\n", read_atoms, atoms_to_read);
        exit(-1);
        return -1;
    }

    atom->epsilon = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->sigma6 = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->cutforcesq = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->cutneighsq = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    for(int i = 0; i < atom->ntypes * atom->ntypes; i++) {
        atom->epsilon[i] = param->epsilon;
        atom->sigma6[i] = param->sigma6;
        atom->cutneighsq[i] = param->cutneigh * param->cutneigh;
        atom->cutforcesq[i] = param->cutforce * param->cutforce;
    }

    fprintf(stdout, "Read %d atoms from %s\n", read_atoms, param->input_file);
    fclose(fp);
    return read_atoms;
}

int readAtom_dmp(Atom* atom, Parameter* param) {
    FILE *fp = fopen(param->input_file, "r");
    char line[MAXLINE];
    int natoms = 0;
    int read_atoms = 0;
    int atom_id = -1;
    int ts = -1;

    if(!fp) {
        fprintf(stderr, "Could not open input file: %s\n", param->input_file);
        exit(-1);
        return -1;
    }

    while(!feof(fp) && ts < 1 && !read_atoms) {
        readline(line, fp);
        if(strncmp(line, "ITEM: ", 6) == 0) {
            char *item = &line[6];

            if(strncmp(item, "TIMESTEP", 8) == 0) {
                readline(line, fp);
                ts = atoi(line);
            } else if(strncmp(item, "NUMBER OF ATOMS", 15) == 0) {
                readline(line, fp);
                natoms = atoi(line);
                atom->Natoms = natoms;
                atom->Nlocal = natoms;
                while(atom->Nlocal >= atom->Nmax) {
                    growAtom(atom);
                }
            } else if(strncmp(item, "BOX BOUNDS pp pp pp", 19) == 0) {
                readline(line, fp);
                param->xlo = atof(strtok(line, " "));
                param->xhi = atof(strtok(NULL, " "));
                param->xprd = param->xhi - param->xlo;

                readline(line, fp);
                param->ylo = atof(strtok(line, " "));
                param->yhi = atof(strtok(NULL, " "));
                param->yprd = param->yhi - param->ylo;

                readline(line, fp);
                param->zlo = atof(strtok(line, " "));
                param->zhi = atof(strtok(NULL, " "));
                param->zprd = param->zhi - param->zlo;
            } else if(strncmp(item, "ATOMS id type x y z vx vy vz", 28) == 0) {
                for(int i = 0; i < natoms; i++) {
                    readline(line, fp);
                    atom_id = atoi(strtok(line, " ")) - 1;
                    atom->type[atom_id] = atoi(strtok(NULL, " "));
                    atom_x(atom_id) = atof(strtok(NULL, " "));
                    atom_y(atom_id) = atof(strtok(NULL, " "));
                    atom_z(atom_id) = atof(strtok(NULL, " "));
                    atom_vx(atom_id) = atof(strtok(NULL, " "));
                    atom_vy(atom_id) = atof(strtok(NULL, " "));
                    atom_vz(atom_id) = atof(strtok(NULL, " "));
                    atom->ntypes = MAX(atom->type[atom_id], atom->ntypes);
                    read_atoms++;
                }
            } else {
                fprintf(stderr, "Invalid item: %s\n", item);
                exit(-1);
                return -1;
            }
        } else {
            fprintf(stderr, "Invalid input from file, expected item reference but got:\n%s\n", line);
            exit(-1);
            return -1;
        }
    }

    if(ts < 0 || !natoms || !read_atoms) {
        fprintf(stderr, "Input error: atom data was not read!\n");
        exit(-1);
        return -1;
    }

    atom->epsilon = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->sigma6 = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->cutforcesq = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->cutneighsq = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    for(int i = 0; i < atom->ntypes * atom->ntypes; i++) {
        atom->epsilon[i] = param->epsilon;
        atom->sigma6[i] = param->sigma6;
        atom->cutneighsq[i] = param->cutneigh * param->cutneigh;
        atom->cutforcesq[i] = param->cutforce * param->cutforce;
    }

    fprintf(stdout, "Read %d atoms from %s\n", natoms, param->input_file);
    return natoms;
}

int readAtom_in(Atom* atom, Parameter* param) {
    FILE *fp = fopen(param->input_file, "r");
    char line[MAXLINE];
    int natoms = 0;
    int atom_id = 0;

    if(!fp) {
        fprintf(stderr, "Could not open input file: %s\n", param->input_file);
        exit(-1);
        return -1;
    }

    readline(line, fp);
    natoms = atoi(strtok(line, " "));
    param->xlo = atof(strtok(NULL, " "));
    param->xhi = atof(strtok(NULL, " "));
    param->ylo = atof(strtok(NULL, " "));
    param->yhi = atof(strtok(NULL, " "));
    param->zlo = atof(strtok(NULL, " "));
    param->zhi = atof(strtok(NULL, " "));
    atom->Natoms = natoms;
    atom->Nlocal = natoms;
    atom->ntypes = 1;

    while(atom->Nlocal >= atom->Nmax) {
        growAtom(atom);
    }

    for(int i = 0; i < natoms; i++) {
        readline(line, fp);

        // TODO: store mass per atom
        char *s_mass = strtok(line, " ");
        if(strncmp(s_mass, "inf", 3) == 0) {
            // Set atom's mass to INFINITY
        } else {
            param->mass = atof(s_mass);
        }

        atom->radius[atom_id] = atof(strtok(NULL, " "));
        atom_x(atom_id) = atof(strtok(NULL, " "));
        atom_y(atom_id) = atof(strtok(NULL, " "));
        atom_z(atom_id) = atof(strtok(NULL, " "));
        atom_vx(atom_id) = atof(strtok(NULL, " "));
        atom_vy(atom_id) = atof(strtok(NULL, " "));
        atom_vz(atom_id) = atof(strtok(NULL, " "));
        atom->type[atom_id] = 0;
        atom->ntypes = MAX(atom->type[atom_id], atom->ntypes);
        atom_id++;
    }

    if(!natoms) {
        fprintf(stderr, "Input error: atom data was not read!\n");
        exit(-1);
        return -1;
    }

    atom->epsilon = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->sigma6 = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->cutforcesq = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    atom->cutneighsq = allocate(ALIGNMENT, atom->ntypes * atom->ntypes * sizeof(MD_FLOAT));
    for(int i = 0; i < atom->ntypes * atom->ntypes; i++) {
        atom->epsilon[i] = param->epsilon;
        atom->sigma6[i] = param->sigma6;
        atom->cutneighsq[i] = param->cutneigh * param->cutneigh;
        atom->cutforcesq[i] = param->cutforce * param->cutforce;
    }

    fprintf(stdout, "Read %d atoms from %s\n", natoms, param->input_file);
    return natoms;
}

void growAtom(Atom *atom) {
    DeviceAtom *d_atom = &(atom->d_atom);
    int nold = atom->Nmax;
    atom->Nmax += DELTA;

    #undef REALLOC
    #define REALLOC(p,t,ns,os); \
        atom->p = (t *) reallocate(atom->p, ALIGNMENT, ns, os); \
        atom->d_atom.p = (t *) reallocateGPU(atom->d_atom.p, ns);

    #ifdef AOS
    REALLOC(x,  MD_FLOAT, atom->Nmax * sizeof(MD_FLOAT) * 3, nold * sizeof(MD_FLOAT) * 3);
    REALLOC(vx, MD_FLOAT, atom->Nmax * sizeof(MD_FLOAT) * 3, nold * sizeof(MD_FLOAT) * 3);
    REALLOC(fx, MD_FLOAT, atom->Nmax * sizeof(MD_FLOAT) * 3, nold * sizeof(MD_FLOAT) * 3);
    #else
    REALLOC(x,  MD_FLOAT, atom->Nmax * sizeof(MD_FLOAT), nold * sizeof(MD_FLOAT));
    REALLOC(y,  MD_FLOAT, atom->Nmax * sizeof(MD_FLOAT), nold * sizeof(MD_FLOAT));
    REALLOC(z,  MD_FLOAT, atom->Nmax * sizeof(MD_FLOAT), nold * sizeof(MD_FLOAT));
    REALLOC(vx, MD_FLOAT, atom->Nmax * sizeof(MD_FLOAT), nold * sizeof(MD_FLOAT));
    REALLOC(vy, MD_FLOAT, atom->Nmax * sizeof(MD_FLOAT), nold * sizeof(MD_FLOAT));
    REALLOC(vz, MD_FLOAT, atom->Nmax * sizeof(MD_FLOAT), nold * sizeof(MD_FLOAT));
    REALLOC(fx, MD_FLOAT, atom->Nmax * sizeof(MD_FLOAT), nold * sizeof(MD_FLOAT));
    REALLOC(fy, MD_FLOAT, atom->Nmax * sizeof(MD_FLOAT), nold * sizeof(MD_FLOAT));
    REALLOC(fz, MD_FLOAT, atom->Nmax * sizeof(MD_FLOAT), nold * sizeof(MD_FLOAT));
    #endif
    REALLOC(type, int, atom->Nmax * sizeof(int), nold * sizeof(int));

    // DEM
    atom->radius = (MD_FLOAT *) reallocate(atom->radius, ALIGNMENT, atom->Nmax * sizeof(MD_FLOAT), nold * sizeof(MD_FLOAT));
    atom->av = (MD_FLOAT*) reallocate(atom->av, ALIGNMENT, atom->Nmax * sizeof(MD_FLOAT) * 3, nold * sizeof(MD_FLOAT) * 3);
    atom->r  = (MD_FLOAT*) reallocate(atom->r,  ALIGNMENT, atom->Nmax * sizeof(MD_FLOAT) * 4, nold * sizeof(MD_FLOAT) * 4);
}
