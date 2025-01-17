.intel_syntax noprefix

.text
.align    16,0x90
.globl computeForce
computeForce:
# parameter 1: rdi Parameter*
# parameter 2: rsi Atom*
# parameter 3: rdx Neighbor*
        push      rbp
        push      r12
        push      r13
        push      r14
        push      r15
        push      rbx
        #call      getTimeStamp                                      # xmm0 <- getTimeStamp()
        #vmovsd    QWORD PTR [-56+rsp], xmm0                         # [-56+rsp] <- xmm0 [spill]
        mov       r9d, DWORD PTR [4+rsi]                            # r9d <- atom->Nlocal
        vmovsd    xmm2, QWORD PTR [96+rdi]                          # xmm2 <- param->cutforce
        vmovsd    xmm1, QWORD PTR [32+rdi]                          # xmm1 <- param->sigma6
        vmovsd    xmm0, QWORD PTR [24+rdi]                          # xmm0 <- param->epsilon
        mov       r13, QWORD PTR [64+rsi]                           # r13 <- atom->fx
        mov       r14, QWORD PTR [72+rsi]                           # r14 <- atom->fy
        mov       rdi, QWORD PTR [80+rsi]                           # rdi <- atom->fz
        test      r9d, r9d                                          # atom->Nlocal <= 0
        jle       ..atom_loop_exit
        xor       r10d, r10d                                        # r10d <- 0
        mov       ecx, r9d                                          # ecx <- atom->Nlocal
        xor       r8d, r8d                                          # r8d <- 0
        mov       r11d, 1                                           # r11d <- 1
        xor       eax, eax                                          # eax <- 0
        shr       ecx, 1                                            # ecx <- atom->Nlocal >> 1
        je        ..zero_last_element                               # ecx == 0

# Init forces to zero loop (unroll factor = 2)
..init_force_loop:
        mov       QWORD PTR [r8+r13], rax                           # fx[i] <- 0
        mov       QWORD PTR [r8+r14], rax                           # fy[i] <- 0
        mov       QWORD PTR [r8+rdi], rax                           # fz[i] <- 0
        mov       QWORD PTR [8+r8+r13], rax                         # fx[i] <- 0
        mov       QWORD PTR [8+r8+r14], rax                         # fy[i] <- 0
        mov       QWORD PTR [8+r8+rdi], rax                         # fz[i] <- 0
        add       r8, 16                                            # i++
        inc       r10                                               # i++
        cmp       r10, rcx                                          # i < Nlocal
        jb        ..init_force_loop

# Trick to make r11d contain value of last element to be zeroed plus 1
# Maybe we can directly put r10+10 here and zero r11d above, then remove the -1 below
        lea       r11d, DWORD PTR [1+r10+r10]                       # r11d <- i * 2 + 1
..zero_last_element:
        lea       ecx, DWORD PTR [-1+r11]                           # ecx <- i * 2
        cmp       ecx, r9d                                          # i >= Nlocal
        jae       ..before_atom_loop

        # Set last element to zero
        movsxd    r11, r11d                                         # r11 <- i * 2
        mov       QWORD PTR [-8+r13+r11*8], rax                     # fx[i] <- 0
        mov       QWORD PTR [-8+r14+r11*8], rax                     # fy[i] <- 0
        mov       QWORD PTR [-8+rdi+r11*8], rax                     # fz[i] <- 0

# Initialize registers to be used within atom loop
..before_atom_loop:
        vmulsd    xmm15, xmm2, xmm2                                 # xmm15 <- cutforcesq
        vmovdqu32 ymm18, YMMWORD PTR .L_2il0floatpacket.0[rip]      # ymm18 <- [8, ...]
        vmulsd    xmm0, xmm0, QWORD PTR .L_2il0floatpacket.3[rip]   # xmm0 <- 48 *  epsilon
        vmovdqu32 ymm17, YMMWORD PTR .L_2il0floatpacket.1[rip]      # ymm17 <- [0..7]
        vmovups   zmm7, ZMMWORD PTR .L_2il0floatpacket.4[rip]       # zmm7 <- [0.5, ...]
        vbroadcastsd zmm16, xmm15                                   # zmm16 <- [cutforcesq, ...]
        vbroadcastsd zmm15, xmm1                                    # zmm15 <- [param->sigma6, ...]
        vbroadcastsd zmm14, xmm0                                    # zmm14 <- [48 * epsilon, ...]
        movsxd    r9, r9d                                           # r9 <- atom->Nlocal
        xor       r10d, r10d                                        # r10d <- 0 (i)
        mov       rcx, QWORD PTR [24+rdx]                           # rcx <- neighbor->numneigh
        mov       r11, QWORD PTR [8+rdx]                            # r11 <- neighbor->neighbors
        movsxd    r12, DWORD PTR [16+rdx]                           # r12 <- neighbor->maxneighs
        mov       rdx, QWORD PTR [16+rsi]                           # rdx <- atom->x
        ### AOS
        xor       eax, eax
        ### SOA
        #mov       rax, QWORD PTR [24+rsi]                          # rax <- atom->y
        #mov       rsi, QWORD PTR [32+rsi]                          # rsi <- atom->z
        ###
        shl       r12, 2                                            # r12 <- neighbor->maxneighs * 4

        # Register spilling
        mov       QWORD PTR [-32+rsp], r9                           # [-32+rsp] <- atom->Nlocal
        mov       QWORD PTR [-24+rsp], rcx                          # [-24+rsp] <- neighbor->numneigh
        mov       QWORD PTR [-16+rsp], r14                          # [-16+rsp] <- atom->fy
        mov       QWORD PTR [-8+rsp], r13                           # [-8+rsp] <- atom->fx
        mov       QWORD PTR [-40+rsp], r15                          # [-40+rsp] <- r15
        mov       QWORD PTR [-48+rsp], rbx                          # [-48+rsp] <- rbx

..atom_loop_begin:
        mov       rcx, QWORD PTR [-24+rsp]                          # rcx <- neighbor->numneigh
        vxorpd    xmm25, xmm25, xmm25                               # xmm25 <- 0 (fix)
        vmovapd   xmm20, xmm25                                      # xmm20 <- 0 (fiy)
        mov       r13d, DWORD PTR [rcx+r10*4]                       # r13d <- neighbor->numneigh[i] (numneighs)
        vmovapd   xmm4, xmm20                                       # xmm4 <- 0 (fiz)

        ### AOS
        vmovsd    xmm8, QWORD PTR[rdx+rax]                          # xmm8 <- atom->x[i * 3]
        vmovsd    xmm9, QWORD PTR[8+rdx+rax]                        # xmm9 <- atom->x[i * 3 + 1]
        vmovsd    xmm10, QWORD PTR[16+rdx+rax]                      # xmm10 <- atom->x[i * 3 + 2]
        ### SOA
        #vmovsd    xmm8, QWORD PTR [rdx+r10*8]                      # xmm8 <- atom->x[i]
        #vmovsd    xmm9, QWORD PTR [rax+r10*8]                      # xmm9 <- atom->y[i]
        #vmovsd    xmm10, QWORD PTR [rsi+r10*8]                     # xmm10 <- atom->z[i]
        ###
        vbroadcastsd zmm0, xmm8                                     # zmm0 <- atom_x(i)
        vbroadcastsd zmm1, xmm9                                     # zmm1 <- atom_y(i)
        vbroadcastsd zmm2, xmm10                                    # zmm2 <- atom_z(i)
        test      r13d, r13d                                        # numneighs <= 0
        jle       ..atom_loop_exit

        vpxord    zmm13, zmm13, zmm13                               # zmm13 <- 0 (fix)
        vmovaps   zmm12, zmm13                                      # zmm12 <- 0 (fiy)
        vmovaps   zmm11, zmm12                                      # zmm11 <- 0 (fiz)
        mov       rcx, r12                                          # rcx <- neighbor->maxneighs * 4
        imul      rcx, r10                                          # rcx <- neighbor->maxneighs * 4 * i
        add       rcx, r11                                          # rcx <- &neighbor->neighbors[neighbor->maxneighs * i]
        xor       r9d, r9d                                          # r9d <- 0 (k)
        mov       r14d, r13d                                        # r14d <- numneighs
        cmp       r14d, 8
        jl        ..compute_forces_remainder

..compute_forces:
        vpcmpeqb  k1, xmm0, xmm0
        vpcmpeqb  k2, xmm0, xmm0
        vpcmpeqb  k3, xmm0, xmm0
        vmovdqu   ymm3, YMMWORD PTR [rcx+r9*4]
        vpxord    zmm5, zmm5, zmm5
        vpxord    zmm6, zmm6, zmm6

        ### AOS
        vpaddd     ymm4, ymm3, ymm3
        vpaddd     ymm3, ymm3, ymm4
        vpxord     zmm4, zmm4, zmm4
        vgatherdpd zmm4{k1}, [rdx+ymm3*8]
        vgatherdpd zmm5{k2}, [8+rdx+ymm3*8]
        vgatherdpd zmm6{k3}, [16+rdx+ymm3*8]
        ### SOA
        #vpxord     zmm4, zmm4, zmm4
        #vgatherdpd zmm5{k2}, [rax+ymm3*8]
        #vgatherdpd zmm4{k1}, [rdx+ymm3*8]
        #vgatherdpd zmm6{k3}, [rsi+ymm3*8]
        ###

        vsubpd    zmm29, zmm1, zmm5                                 # zmm29 <- atom_y(i) - atom_y(j) -- dely
        vsubpd    zmm28, zmm0, zmm4                                 # zmm28 <- atom_x(i) - atom_x(j) -- delx
        vsubpd    zmm31, zmm2, zmm6                                 # zmm31 <- atom_z(i) - atom_z(j) -- delz
        vmulpd    zmm20, zmm29, zmm29                               # zmm20 <- dely * dely
        vfmadd231pd zmm20, zmm28, zmm28                             # zmm20 <- dely * dely + delx * delx
        vfmadd231pd zmm20, zmm31, zmm31                             # zmm20 <- zmm20 + delz * delz --  rsq

        # Cutoff radius condition
        vrcp14pd  zmm27, zmm20                                      # zmm27 <- 1.0 / rsq (sr2)
        vcmppd    k5, zmm20, zmm16, 1                               # k5 <- rsq < cutforcesq
        vmulpd    zmm22, zmm27, zmm15                               # zmm22 <-  sr2 * sigma6
        vmulpd    zmm24, zmm27, zmm14                               # zmm24 <- 48.0 * epsilon * sr2
        vmulpd    zmm25, zmm27, zmm22                               # zmm25 <- sr2 * sigma6 * sr2
        vmulpd    zmm23, zmm27, zmm25                               # zmm23 <- sr2 * sigma6 * sr2 * sr2
        vfmsub213pd zmm27, zmm25, zmm7                              # zmm27 <- sr2 * sigma * sr2 * sr2 - 0.5
        vmulpd    zmm26, zmm23, zmm24                               # zmm26 <- 48.0 * epsilon * sr2 * sr2 * sigma6 * sr2
        vmulpd    zmm30, zmm26, zmm27                               # zmm30 <- force
        vfmadd231pd zmm13{k5}, zmm30, zmm28                         # fix += force * delx
        vfmadd231pd zmm12{k5}, zmm30, zmm29                         # fiy += force * dely
        vfmadd231pd zmm11{k5}, zmm30, zmm31                         # fiz += force * delz
        sub       r14d, 8
        add       r9, 8
        cmp       r14d, 8
        jge       ..compute_forces

# Check if there are remaining neighbors to be computed
..compute_forces_remainder:
        test      r14d, r14d
        jle       ..sum_up_forces

        vpbroadcastd ymm4, r14d
        vpcmpgtd  k1, ymm4, ymm17
        kmovw     r15d, k1
        vmovdqu32 ymm3{k1}{z}, YMMWORD PTR [rcx+r9*4]
        kmovw     k2, k1
        kmovw     k3, k1
        vpxord    zmm5, zmm5, zmm5
        vpxord    zmm6, zmm6, zmm6

        ### AOS
        vpaddd     ymm4, ymm3, ymm3
        vpaddd     ymm3, ymm3, ymm4
        vpxord     zmm4, zmm4, zmm4
        vgatherdpd zmm4{k1}, [rdx+ymm3*8]
        vgatherdpd zmm5{k2}, [8+rdx+ymm3*8]
        vgatherdpd zmm6{k3}, [16+rdx+ymm3*8]
        #### SOA
        #vpxord     zmm4, zmm4, zmm4
        #vgatherdpd zmm5{k2}, [rax+ymm3*8]
        #vgatherdpd zmm4{k1}, [rdx+ymm3*8]
        #vgatherdpd zmm6{k3}, [rsi+ymm3*8]
        ###

        vsubpd    zmm29, zmm1, zmm5                                 # zmm29 <- atom_y(i) - atom_y(j) -- dely
        vsubpd    zmm28, zmm0, zmm4                                 # zmm28 <- atom_x(i) - atom_x(j) -- delx
        vsubpd    zmm31, zmm2, zmm6                                 # zmm31 <- atom_z(i) - atom_z(j) -- delz
        vmulpd    zmm20, zmm29, zmm29                               # zmm20 <- dely * dely
        vfmadd231pd zmm20, zmm28, zmm28                             # zmm20 <- dely * dely + delx * delx
        vfmadd231pd zmm20, zmm31, zmm31                             # zmm20 <- zmm20 + delz * delz --  rsq

        # Cutoff radius condition
        vrcp14pd  zmm27, zmm20                                      # zmm27 <- 1.0 / rsq (sr2)
        vcmppd    k5, zmm20, zmm16, 1                               # k5 <- rsq < cutforcesq
        kmovw     r9d, k5                                           # r9d <- rsq < cutforcesq
        and       r15d, r9d                                         # r15d <- rsq < cutforcesq && k < numneighs
        kmovw     k3, r15d                                          # k3 <- rsq < cutforcesq && k < numneighs
        vmulpd    zmm22, zmm27, zmm15                               # zmm22 <-  sr2 * sigma6
        vmulpd    zmm24, zmm27, zmm14                               # zmm24 <- 48.0 * epsilon * sr2
        vmulpd    zmm25, zmm27, zmm22                               # zmm25 <- sr2 * sigma6 * sr2
        vmulpd    zmm23, zmm27, zmm25                               # zmm23 <- sr2 * sigma6 * sr2 * sr2
        vfmsub213pd zmm27, zmm25, zmm7                              # zmm27 <- sr2 * sigma * sr2 * sr2 - 0.5
        vmulpd    zmm26, zmm23, zmm24                               # zmm26 <- 48.0 * epsilon * sr2 * sr2 * sigma6 * sr2
        vmulpd    zmm30, zmm26, zmm27                               # zmm30 <- force
        vfmadd231pd zmm13{k3}, zmm30, zmm28                         # fix += force * delx
        vfmadd231pd zmm12{k3}, zmm30, zmm29                         # fiy += force * dely
        vfmadd231pd zmm11{k3}, zmm30, zmm31                         # fiz += force * delz

# Forces are currently separated in different lanes of zmm registers, hence it is necessary to permutate
# and add them (reduction) to obtain the final contribution for the current atom
..sum_up_forces:
        vmovups   zmm10, ZMMWORD PTR .L_2il0floatpacket.6[rip]
        vpermd    zmm0, zmm10, zmm11
        vpermd    zmm5, zmm10, zmm12
        vpermd    zmm21, zmm10, zmm13
        vaddpd    zmm11, zmm0, zmm11
        vaddpd    zmm12, zmm5, zmm12
        vaddpd    zmm13, zmm21, zmm13
        vpermpd   zmm1, zmm11, 78
        vpermpd   zmm6, zmm12, 78
        vpermpd   zmm22, zmm13, 78
        vaddpd    zmm2, zmm11, zmm1
        vaddpd    zmm8, zmm12, zmm6
        vaddpd    zmm23, zmm13, zmm22
        vpermpd   zmm3, zmm2, 177
        vpermpd   zmm9, zmm8, 177
        vpermpd   zmm24, zmm23, 177
        vaddpd    zmm4, zmm2, zmm3
        vaddpd    zmm20, zmm8, zmm9
        vaddpd    zmm25, zmm23, zmm24

..atom_loop_exit:
        mov       rcx, QWORD PTR [-8+rsp]                       #84.9[spill]
        mov       rbx, QWORD PTR [-16+rsp]                      #85.9[spill]

        ### AOS
        add       rax, 24
        ###

        vaddsd    xmm0, xmm25, QWORD PTR [rcx+r10*8]            #84.9
        vmovsd    QWORD PTR [rcx+r10*8], xmm0                   #84.9
        vaddsd    xmm1, xmm20, QWORD PTR [rbx+r10*8]            #85.9
        vmovsd    QWORD PTR [rbx+r10*8], xmm1                   #85.9
        vaddsd    xmm2, xmm4, QWORD PTR [rdi+r10*8]             #86.9
        vmovsd    QWORD PTR [rdi+r10*8], xmm2                   #86.9
        inc       r10                                           #55.5
        cmp       r10, QWORD PTR [-32+rsp]                      #55.5[spill]
        jb        ..atom_loop_begin
        vzeroupper                                              #93.12
        vxorpd    xmm0, xmm0, xmm0                              #93.12
        #call      getTimeStamp                                  # xmm0 <- getTimeStamp()
        #vsubsd    xmm0, xmm0, QWORD PTR [-56+rsp]               # xmm0 <- E-S
        pop       rbx
        pop       r15
        pop       r14                                           #93.12
        pop       r13                                           #93.12
        pop       r12                                           #93.12
        pop       rbp                                           #93.12
        ret                                                     #93.12

.type	computeForce,@function
.size	computeForce,.-computeForce


..LNcomputeForce.0:
	.data
# -- End  computeForce
	.section .rodata, "a"
	.align 64
	.align 64
.L_2il0floatpacket.2:
	.long	0x00000000,0x3ff00000,0x00000000,0x3ff00000,0x00000000,0x3ff00000,0x00000000,0x3ff00000,0x00000000,0x3ff00000,0x00000000,0x3ff00000,0x00000000,0x3ff00000,0x00000000,0x3ff00000
	.type	.L_2il0floatpacket.2,@object
	.size	.L_2il0floatpacket.2,64
	.align 64
.L_2il0floatpacket.4:
	.long	0x00000000,0x3fe00000,0x00000000,0x3fe00000,0x00000000,0x3fe00000,0x00000000,0x3fe00000,0x00000000,0x3fe00000,0x00000000,0x3fe00000,0x00000000,0x3fe00000,0x00000000,0x3fe00000
	.type	.L_2il0floatpacket.4,@object
	.size	.L_2il0floatpacket.4,64
	.align 64
.L_2il0floatpacket.6:
	.long	0x00000008,0x00000009,0x0000000a,0x0000000b,0x0000000c,0x0000000d,0x0000000e,0x0000000f,0x00000008,0x00000009,0x0000000a,0x0000000b,0x0000000c,0x0000000d,0x0000000e,0x0000000f
	.type	.L_2il0floatpacket.6,@object
	.size	.L_2il0floatpacket.6,64
	.align 32
.L_2il0floatpacket.0:
	.long	0x00000008,0x00000008,0x00000008,0x00000008,0x00000008,0x00000008,0x00000008,0x00000008
	.type	.L_2il0floatpacket.0,@object
	.size	.L_2il0floatpacket.0,32
	.align 32
.L_2il0floatpacket.1:
	.long	0x00000000,0x00000001,0x00000002,0x00000003,0x00000004,0x00000005,0x00000006,0x00000007
	.type	.L_2il0floatpacket.1,@object
	.size	.L_2il0floatpacket.1,32
	.align 8
.L_2il0floatpacket.3:
	.long	0x00000000,0x40480000
	.type	.L_2il0floatpacket.3,@object
	.size	.L_2il0floatpacket.3,8
	.align 8
.L_2il0floatpacket.5:
	.long	0x00000000,0x3ff00000
	.type	.L_2il0floatpacket.5,@object
	.size	.L_2il0floatpacket.5,8
	.data
	.section .note.GNU-stack, ""
# End
