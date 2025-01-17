/*
 * Copyright (C) 2022 NHR@FAU, University Erlangen-Nuremberg.
 * All rights reserved. This file is part of MD-Bench.
 * Use of this source code is governed by a LGPL-3.0
 * license that can be found in the LICENSE file.
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
//---
#include <cuda_profiler_api.h>
#include <cuda_runtime.h>
#include <device_launch_parameters.h>
//---
#include <likwid-marker.h>

extern "C" {

#include <allocate.h>
#include <atom.h>
#include <allocate.h>
#include <device.h>
#include <neighbor.h>
#include <parameter.h>
#include <timing.h>
#include <util.h>

}

// cuda kernel
__global__ void calc_force(DeviceAtom a, MD_FLOAT cutforcesq, MD_FLOAT sigma6, MD_FLOAT epsilon, int Nlocal, int neigh_maxneighs, int *neigh_neighbors, int *neigh_numneigh) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if(i >= Nlocal) {
        return;
    }

    DeviceAtom *atom = &a;
    const int numneighs = neigh_numneigh[i];

    MD_FLOAT xtmp = atom_x(i);
    MD_FLOAT ytmp = atom_y(i);
    MD_FLOAT ztmp = atom_z(i);

    MD_FLOAT fix = 0;
    MD_FLOAT fiy = 0;
    MD_FLOAT fiz = 0;

    for(int k = 0; k < numneighs; k++) {
        int j = neigh_neighbors[Nlocal * k + i];
        MD_FLOAT delx = xtmp - atom_x(j);
        MD_FLOAT dely = ytmp - atom_y(j);
        MD_FLOAT delz = ztmp - atom_z(j);
        MD_FLOAT rsq = delx * delx + dely * dely + delz * delz;

#ifdef EXPLICIT_TYPES
        const int type_j = atom->type[j];
        const int type_ij = type_i * atom->ntypes + type_j;
        const MD_FLOAT cutforcesq = atom->cutforcesq[type_ij];
        const MD_FLOAT sigma6 = atom->sigma6[type_ij];
        const MD_FLOAT epsilon = atom->epsilon[type_ij];
#endif

        if(rsq < cutforcesq) {
            MD_FLOAT sr2 = 1.0 / rsq;
            MD_FLOAT sr6 = sr2 * sr2 * sr2 * sigma6;
            MD_FLOAT force = 48.0 * sr6 * (sr6 - 0.5) * sr2 * epsilon;
            fix += delx * force;
            fiy += dely * force;
            fiz += delz * force;
        }
    }

    atom_fx(i) = fix;
    atom_fy(i) = fiy;
    atom_fz(i) = fiz;
}

__global__ void kernel_initial_integrate(MD_FLOAT dtforce, MD_FLOAT dt, int Nlocal, DeviceAtom a) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if( i >= Nlocal ) {
        return;
    }

    DeviceAtom *atom = &a;

    atom_vx(i) += dtforce * atom_fx(i);
    atom_vy(i) += dtforce * atom_fy(i);
    atom_vz(i) += dtforce * atom_fz(i);
    atom_x(i) = atom_x(i) + dt * atom_vx(i);
    atom_y(i) = atom_y(i) + dt * atom_vy(i);
    atom_z(i) = atom_z(i) + dt * atom_vz(i);
}

__global__ void kernel_final_integrate(MD_FLOAT dtforce, int Nlocal, DeviceAtom a) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if( i >= Nlocal ) {
        return;
    }

    DeviceAtom *atom = &a;

    atom_vx(i) += dtforce * atom_fx(i);
    atom_vy(i) += dtforce * atom_fy(i);
    atom_vz(i) += dtforce * atom_fz(i);
}

extern "C" {

void finalIntegrate_cuda(bool reneigh, Parameter *param, Atom *atom) {
    const int Nlocal = atom->Nlocal;
    const int num_threads_per_block = get_num_threads();
    const int num_blocks = ceil((float)Nlocal / (float)num_threads_per_block);

    kernel_final_integrate <<< num_blocks, num_threads_per_block >>> (param->dtforce, Nlocal, atom->d_atom);
    cuda_assert("kernel_final_integrate", cudaPeekAtLastError());
    cuda_assert("kernel_final_integrate", cudaDeviceSynchronize());

    if(reneigh) {
        memcpyFromGPU(atom->vx, atom->d_atom.vx, sizeof(MD_FLOAT) * atom->Nlocal * 3);
    }
}

void initialIntegrate_cuda(bool reneigh, Parameter *param, Atom *atom) {
    const int Nlocal = atom->Nlocal;
    const int num_threads_per_block = get_num_threads();
    const int num_blocks = ceil((float)Nlocal / (float)num_threads_per_block);

    kernel_initial_integrate <<< num_blocks, num_threads_per_block >>> (param->dtforce, param->dt, Nlocal, atom->d_atom);
    cuda_assert("kernel_initial_integrate", cudaPeekAtLastError());
    cuda_assert("kernel_initial_integrate", cudaDeviceSynchronize());

    if(reneigh) {
        memcpyFromGPU(atom->vx, atom->d_atom.vx, sizeof(MD_FLOAT) * atom->Nlocal * 3);
    }
}

double computeForceLJFullNeigh_cuda(Parameter *param, Atom *atom, Neighbor *neighbor) {
    const int num_threads_per_block = get_num_threads();
    int Nlocal = atom->Nlocal;
#ifndef EXPLICIT_TYPES
    MD_FLOAT cutforcesq = param->cutforce * param->cutforce;
    MD_FLOAT sigma6 = param->sigma6;
    MD_FLOAT epsilon = param->epsilon;
#endif

    /*
    int nDevices;
    cudaGetDeviceCount(&nDevices);
    size_t free, total;
    for(int i = 0; i < nDevices; ++i) {
        cudaMemGetInfo( &free, &total );
        cudaDeviceProp prop;
        cudaGetDeviceProperties(&prop, i);
        printf("DEVICE %d/%d NAME: %s\r\n with %ld MB/%ld MB memory used", i + 1, nDevices, prop.name, free / 1024 / 1024, total / 1024 / 1024);
    }
    */


    // HINT: Run with cuda-memcheck ./MDBench-NVCC in case of error
    // memsetGPU(atom->d_atom.fx, 0, sizeof(MD_FLOAT) * Nlocal * 3);

    cudaProfilerStart();
    const int num_blocks = ceil((float)Nlocal / (float)num_threads_per_block);
    double S = getTimeStamp();
    LIKWID_MARKER_START("force");

    calc_force <<< num_blocks, num_threads_per_block >>> (atom->d_atom, cutforcesq, sigma6, epsilon, Nlocal, neighbor->maxneighs, neighbor->d_neighbor.neighbors, neighbor->d_neighbor.numneigh);
    cuda_assert("calc_force", cudaPeekAtLastError());
    cuda_assert("calc_force", cudaDeviceSynchronize());
    cudaProfilerStop();

    LIKWID_MARKER_STOP("force");
    double E = getTimeStamp();
    return E-S;
}

}
